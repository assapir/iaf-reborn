# The pilot's checklist notebook in the flight (modern-iaf/docs/training.md §11), a child of sim_flight.gd:
# - the notebook (notebook.gd) with START-UP (the mission's start-up checklist, or the jet's from its start-up
#   mission: done steps ticked, the current one marked, its fault in red), TAXI / T-O (the base's take-off mission's
#   steps), RADIO (the base's frequencies, the calls and the tower's answers), LANDING, EMERGENCY (data/notebook.json)
#   and DATA (the mission's figures);
# - stowed: a board on the pilot's right thigh in the 3D cockpit (the notebook drawn into a texture when it changes);
#   raised by the Checklist notebook key (H, keys.json record 118): a panel at the screen's lower right (in
#   Hebrew too: the thigh's side), never its centre; a start-up mission starts with it raised;
# - in a start-up training mission a ring on the current step's switch (and the gauge it watches), from the part's
#   bounds through the camera every frame; a part out of the view gets a pointer at the screen's edge; the raised
#   board slides along its side off a ring it would cover;
# - a help line over the board in the pilot's first start-up mission only (Settings.notebook_help_seen).
extends Node

const Notebook := preload("notebook.gd")
const Look := preload("../menu/look.gd")
## The sim's key record of the Checklist notebook key (modern-iaf/data/keys.json, command 203).
const KEY := 118
const DATA := "res://data/notebook.json"
## The raised board's inset from the screen's inline-end and bottom edges (px at the 1080-high canvas).
const MARGIN := Vector2(26, 18)
## A ring: this far (px) outside the part's projected bounds; the board keeps GAP px off it.
const RING_PAD := 6.0
const GAP := 18.0
## The least of the slid board left on the screen (px).
const MIN_SHOWN := 220.0
const RING := Color("6699ff")
const NAVY := Color(0, 0, 0.333, 0.85)
const JETS := {"f16i": "F-16I", "f16d": "F-16D", "f35i": "F-35I"}

var flight: Node  # sim_flight.gd
var board: Notebook
var raised := false
var data := {}
## The rings and pointers of this frame: [{rect: canvas Rect2 of the part (a ring) or null, at: Vector2 (a pointer's
## place), text, dir: Vector2}].
var marks: Array = []
var _holder: Control  # the raised board's place on the flight's text layer
var _overlay: Control  # the rings, the pointers, the help line
var _help: PanelContainer
var _vp: SubViewport
var _quad: MeshInstance3D
var _y := -1.0  # the raised board's top (canvas px), sliding
var _missions := {}  # data/missions/*.json, by name


func _init(f: Node) -> void:
	flight = f
	name = "Kneeboard"


func _ready() -> void:
	data = Settings.load_json(DATA)
	for f in DirAccess.get_files_at("res://data/missions"):
		if f.ends_with(".json"):
			_missions[f.get_basename()] = Settings.load_json("res://data/missions/" + f)
	board = Notebook.new()
	_holder = Control.new()
	_holder.name = "Checklist"
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flight.ui.add_child(_holder)
	_overlay = Control.new()
	_overlay.name = "Marks"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_marks)
	flight.ui.add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vp = SubViewport.new()
	_vp.size = Vector2i(int(Notebook.W), int(Notebook.H))
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_vp)
	board.turned.connect(_changed)
	flight.ui.language_changed.connect(refresh)
	set_raised(is_startup())  # in the tree before its pages are measured
	refresh()
	if is_startup() and not Settings.notebook_help_seen:
		Settings.notebook_help_seen = true
		Settings.save()
		_help_line()


func he() -> bool:
	return Settings.language == "he"


func lang() -> String:
	return "he" if he() else "en"


## A start-up mission: the notebook opens raised at its START-UP page and replaces the old step card.
func is_startup() -> bool:
	return not flight.checklist.is_empty()


func toggle() -> void:
	set_raised(not raised)


func set_raised(on: bool) -> void:
	raised = on
	var parent: Node = _holder if on else _vp
	if board.get_parent() != parent:
		if board.get_parent() != null:
			board.get_parent().remove_child(board)
		parent.add_child(board)
		board.position = Vector2.ZERO
	_holder.visible = on
	_y = -1.0
	_changed()


## The pages again from the flight's state (a step taken, a fault, the language).
func refresh() -> void:
	board.set_sections(_sections(), he())
	if is_startup() and board.current_id() == "startup":
		board.open("startup", _current())  # the page holding the step to take now
	if _help != null:
		_help.queue_free()
		_help = null
		_help_line()


## PgUp / PgDn turn the raised notebook's pages (true: taken).
func key(event: InputEventKey) -> bool:
	if not raised or not event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN]:
		return false
	board.turn(1 if event.keycode == KEY_PAGEDOWN else -1)
	return true


func _changed() -> void:
	if not raised:
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


# --- the pages --------------------------------------------------------------------------------------------------------


func s(key: String) -> String:
	return flight.ui.s(key)


func _jet() -> String:
	return JETS.get(flight.plane, flight.plane.to_upper())


func _family() -> String:
	return "f35i" if flight.plane == "f35i" else "f16"


func _readable() -> Dictionary:
	return _missions.get(flight.mission_name, _missions.get(_mission_file(), {}))


## The flight's readable mission file's name (sim_flight's mission_name is set for training missions only).
func _mission_file() -> String:
	var files: Array = flight.MissionRuntime.mission_files(flight.host.mission_id)
	return String(files[0].name) if not files.is_empty() else ""


func _base() -> String:
	return String(_readable().get("start", {}).get("base", ""))


## The training mission of `kind` for the flight's base (else its jet): its readable data, {} when none.
func _mission_of(kind: String) -> Dictionary:
	var mine := _readable()
	if String(mine.get("training", {}).get("kind", "")) == kind:
		return mine
	var by_jet := {}
	for m in _missions.values():
		if String(m.get("training", {}).get("kind", "")) != kind:
			continue
		if String(m.get("start", {}).get("base", "")) == _base():
			return m
		if String(m.get("start", {}).get("unit", "")) == flight.plane:
			by_jet = m
	return by_jet


## The checklist the START-UP page shows: the flight's own, else its jet's start-up mission's.
func checklist() -> Array:
	if is_startup():
		return flight.checklist
	var m := _mission_of("startup")
	if String(m.get("start", {}).get("unit", "")) != flight.plane:
		return []
	return m.get("training", {}).get("checklist", [])


## The first checklist step not taken (its index; the list's size when all are).
func _current() -> int:
	var list := checklist()
	var i := 0
	while i < list.size() and String(list[i].step) in flight.done:
		i += 1
	return i


func _sections() -> Array:
	var l := lang()
	var secs := []
	var runway := String(flight._sim.get("runway", "")) if flight._sim.get("runway") is String else ""
	var to := _mission_of("takeoff")
	if runway == "":
		runway = String(to.get("runway", ""))
	# START-UP
	var blocks := []
	var list := checklist()
	var cur := _current()
	for i in list.size():
		var c: Dictionary = list[i]
		var state := "done" if String(c.step) in flight.done else ("cur" if i == cur else "")
		var lines := []
		if c.has("where"):
			lines.append(String(c.where[l]))
		if c.has("wait"):
			lines.append("[i]%s[/i]" % _esc(String(c.wait[l])))
		var fault := ""
		if state == "cur" and flight._fault_shown != "" and flight.trainer != null:
			fault = String(flight.trainer.text(flight._fault_shown, l))
		blocks.append(step(i, String(c[l]), lines, state, fault))
	secs.append(_sec("startup", "nb_startup", "%s · %s" % [s("nb_startup"), _jet()], blocks))
	# TAXI / T-O
	blocks = []
	var tol := str(int(to.get("training", {}).get("heading_tolerance_deg", 10)))
	var steps: Array = to.get("training", {}).get("steps", [])
	for i in steps.size():
		var st: Dictionary = steps[i]
		var lines := []
		if st.has("wait"):
			lines.append("[i]%s[/i]" % _esc(_fill(String(st.wait[l]), runway, tol)))
		blocks.append(step(i, _fill(String(st[l]), runway, tol), lines, "", ""))
	var rwy := _runway(runway)
	if not rwy.is_empty():
		blocks.append(table([[s("nb_runway"), rwy.text]], 2))
	secs.append(_sec("taxi", "nb_taxi", "%s · %s" % [s("nb_taxi"), _base_name().to_upper()], blocks))
	# RADIO
	blocks = []
	var cs: String = flight.host.radio.formation_name(flight.host.radio._player_ent()) if flight.host.radio else "Alpha"
	var rows := [[s("nb_callsign"), "[b]%s[/b]" % _ltr(cs.to_upper()), ""]]
	for f in data.get("radio", {}).get(_base(), []):
		var mhz := float(f[1])
		rows.append(["%s %s" % [_base_name(), f[0]], _ltr("%.3f" % mhz), "VHF" if mhz < 136.0 else "UHF"])
	blocks.append(table(rows, 3))
	rows = [["[b]%s[/b]" % s("nb_you_call"), "[b]%s[/b]" % s("nb_on"), "[b]%s[/b]" % s("nb_answer")]]
	for c in data.get("calls", []):
		var said := String(c[l]).replace("{cs}", _ltr(cs)).replace("{runway}", _ltr(runway))
		var item: Array = flight.ITEMS.filter(func(it): return it[0] == c.call)
		rows.append([String(item[0][2 if he() else 1]) if not item.is_empty() else "", c.on, said])
	blocks.append(table(rows, 3))
	secs.append(_sec("radio", "nb_radio", "%s · %s" % [s("nb_radio"), _base_name().to_upper()], blocks))
	# LANDING, EMERGENCY
	var pages: Dictionary = data.get("pages", {}).get(_family(), {})
	blocks = []
	for i in pages.get("landing", []).size():
		var st: Dictionary = pages.landing[i]
		var lines := []
		for k in ["where", "wait"]:
			if st.has(k):
				lines.append(("[i]%s[/i]" if k == "wait" else "%s") % _esc(String(st[k][l])))
		blocks.append(step(i, String(st[l]), lines, "", ""))
	secs.append(_sec("landing", "nb_landing", s("nb_landing"), blocks))
	blocks = []
	for e in pages.get("emergency", []):
		blocks.append("[font_size=16][color=#a31515][b]%s[/b][/color][/font_size]" % _esc(String(e.title[l])))
		for i in e.steps.size():
			blocks.append(step(i, String(e.steps[i][l]), [], "", ""))
	var em := _sec("emergency", "nb_emergency", s("nb_emergency"), blocks)
	em["red"] = true
	secs.append(em)
	# DATA
	var m := _readable()
	rows = []
	rows.append([s("nb_mission"), _esc(String(m.get("title", {}).get(l, "")))])
	rows.append([s("nb_base"), "%s (%s)" % [_base_name(), _ltr(String(rwy.get("icao", "")))]])
	rows.append([s("nb_time"), _ltr(String(m.get("time", "")))])
	var wind := int(m.get("wind_kt", 0))
	rows.append([s("nb_wind"), s("nb_calm") if wind == 0 else _ltr("%03d° / %d kt" % [int(m.wind_from), wind])])
	rows.append([s("nb_jet"), _ltr(_jet())])
	if not rwy.is_empty():
		rows.append([s("nb_runway"), rwy.text])
	var route: Array = m.get("route", [])
	if not route.is_empty():
		var p: Dictionary = route[0]
		rows.append([s("nb_route"), _ltr("%s · %d ft" % [_latlon(p.lat, p.lon), int(float(p.alt_m) / 0.3048)])])
	secs.append(_sec("data", "nb_data", s("nb_data"), [table(rows, 2)]))
	return secs


func _sec(id: String, tab_key: String, title: String, blocks: Array) -> Dictionary:
	return {"id": id, "tab": s(tab_key), "title": title, "blocks": blocks}


func _base_name() -> String:
	var n: Array = flight.BASE_NAMES.values().filter(func(b): return b[0] == _base())
	return String(n[0][1 if he() else 0]) if not n.is_empty() else _base()


## The runway end `designator` of the flight's base: {text: "25R · 246° · 2,700 m · 2,080 ft", icao}; {} without. The
## heading is the grid one the HUD and the compass read (the compiled bases', _grid_heading), not the data's true one.
func _runway(designator: String) -> Dictionary:
	if _base() == "":
		return {}
	for f in DirAccess.get_files_at("res://data/airbases"):
		var b := Settings.load_json("res://data/airbases/" + f)
		if not String(b.get("name", {}).get("en", "")).begins_with(_base()):
			continue
		for r in b.get("runways", []):
			for e in r.get("ends", []):
				if String(e.designator) == designator:
					var length := int(r.get("length_published_m", r.get("length_m", 0)))
					var t := (
						"%s · %03d° · %s m · %s ft"
						% [
							designator,
							roundi(_grid_heading(String(b.get("icao", "")), designator, float(e.heading))),
							_thousands(length),
							_thousands(roundi(float(e.elevation_m) / 0.3048))
						]
					)
					return {"text": _ltr(t), "icao": String(b.get("icao", ""))}
		return {"text": "", "icao": String(b.get("icao", ""))}
	return {}


## The grid heading of base `icao`'s runway end `designator` from the compiled bases (airbases.gd: the sim's world is
## grid north); `fallback` (the data's true heading) without them.
static func _grid_heading(icao: String, designator: String, fallback: float) -> float:
	for b: Dictionary in load("res://shared/terrain/airbases.gd").bases():
		if String(b.get("icao", "")) != icao:
			continue
		for r: Dictionary in b.get("runways", []):
			var k: int = Array(r.get("designators", [])).find(designator)
			if k >= 0:
				return fposmod(float(r.heading) + 180.0 * k, 360.0)
	return fallback


static func _thousands(n: int) -> String:
	var t := str(n)
	return t if t.length() <= 3 else t.left(t.length() - 3) + "," + t.right(3)


static func _latlon(lat: float, lon: float) -> String:
	var f := func(v: float, pos: String, neg: String, w: int) -> String:
		var a := absf(v)
		return "%s%0*d°%05.2f′" % [pos if v >= 0 else neg, w, int(a), (a - int(a)) * 60.0]
	return "%s %s" % [f.call(lat, "N", "S", 2), f.call(lon, "E", "W", 3)]


func _fill(t: String, runway: String, tol: String) -> String:
	return _esc(t).replace("{runway}", _ltr(runway)).replace("{tolerance}", tol)


## A Latin run (a callsign, a figure) kept whole and left to right in a Hebrew line.
func _ltr(t: String) -> String:
	return "\u2066%s\u2069" % t if he() else t


static func _esc(t: String) -> String:
	return t.replace("[", "[lb]")


## A checklist step's block: its mark (✓ done, ▶ current, else its number), its line in bold and the lines under it
## small; the current step on a yellow band, a fault in red under it.
func step(i: int, text: String, lines: Array, state: String, fault: String) -> String:
	var mark := str(i + 1)
	var ink := "#1b1b1b"
	if state == "done":
		mark = "[color=#1e7a32]✓[/color]"
		ink = "#6b675e"
	elif state == "cur":
		mark = "◀" if he() else "▶"
	var under := ""
	for x in lines:
		under += "\n[font_size=%d][color=#444444]%s[/color][/font_size]" % [Notebook.SMALL_PX, x]
	if fault != "":
		under += "\n[font_size=13][color=#b3261e][b]%s[/b][/color][/font_size]" % _esc(fault)
	var bg := " bg=#ffe27a" if state == "cur" else ""
	var head := "[table=2][cell padding=4,5,6,5%s][b]%s[/b][/cell]" % [bg, mark]
	return (
		head
		+ "[cell expand=9 padding=0,5,4,5%s][color=%s][b]%s[/b]%s[/color][/cell][/table]" % [bg, ink, _esc(text), under]
	)


## A table block: `rows` of `cols` cells (BBCode), the first column bold.
static func table(rows: Array, cols: int) -> String:
	var t := "[table=%d]" % cols
	for r in rows:
		for c in cols:
			var v := String(r[c]) if c < r.size() else ""
			var expand := " expand=1" if c == cols - 1 else ""
			t += (
				"[cell padding=2,4,8,4%s][font_size=13]%s[/font_size][/cell]"
				% [expand, "[b]%s[/b]" % v if c == 0 else v]
			)
	return t + "[/table]"


# --- the help line ----------------------------------------------------------------------------------------------------


func _help_line() -> void:
	_help = PanelContainer.new()
	_help.name = "Help"
	_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help.add_theme_stylebox_override("panel", Look.box(Color(Look.BG, 0.88), Look.LINE, 1, 6, Vector2(8, 4)))
	var l := Label.new()
	l.text = s("nb_help") % flight.ui.key_name(KEY)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Look.MUTED)
	l.text_direction = Control.TEXT_DIRECTION_RTL if he() else Control.TEXT_DIRECTION_LTR
	_help.add_child(l)
	_holder.add_child(_help)
	_help.custom_minimum_size.x = Notebook.W
	_help.position = Vector2(0, -36)


# --- every frame: the raised board's place, the 3D board, the rings ---------------------------------------------


func _process(delta: float) -> void:
	_stowed_board()
	marks = _marks()
	_overlay.queue_redraw()
	if not raised:
		return
	var view: Vector2 = flight.ui.size
	var x: float = view.x - Notebook.W - MARGIN.x  # the right side in both languages: the thigh's side (the mock-up)
	var home: float = view.y - Notebook.H - MARGIN.y
	var want := home
	var r := Rect2(x, home, Notebook.W, Notebook.H)
	for m in marks:
		if m.rect != null and r.grow(GAP).intersects(m.rect):
			# Below the ring when enough of the board stays on the screen there, else above it.
			want = (
				m.rect.end.y + GAP
				if view.y - (m.rect.end.y + GAP) >= MIN_SHOWN
				else m.rect.position.y - GAP - Notebook.H
			)
	_y = want if _y < 0.0 else lerpf(_y, want, minf(1.0, delta * 10.0))
	_holder.position = Vector2(x, _y)


## The 3D board on the right thigh: made once the 3D cockpit is up (its place in data/notebook.json "stowed"), shown
## while the notebook is stowed.
func _stowed_board() -> void:
	var c3d = flight.host.get("cockpit_3d")
	if not is_instance_valid(_quad) and is_instance_valid(c3d):
		var at: Dictionary = data.get("stowed", {}).get(_family(), {})
		if at.is_empty():
			return
		var w := float(at.width_m)
		var q := QuadMesh.new()
		q.size = Vector2(w, w * Notebook.H / Notebook.W)
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = _vp.get_texture()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.62, 0.62, 0.62)  # in the cockpit's shade (inferred, matched by eye to the mock-up)
		_quad = MeshInstance3D.new()
		_quad.name = "Kneeboard"
		_quad.mesh = q
		_quad.material_override = mat
		_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var p: Array = at.position
		var rot: Array = at.rotation_deg
		_quad.position = Vector3(p[0], p[1], p[2])
		_quad.rotation_degrees = Vector3(rot[0], rot[1], rot[2])
		c3d.add_child(_quad)
	if is_instance_valid(_quad):
		_quad.visible = not raised


## The rings and pointers of this frame (a start-up training mission's current step only).
func _marks() -> Array:
	var out := []
	var c3d = flight.host.get("cockpit_3d")
	var list := checklist()
	var i := _current()
	if not is_startup() or flight.rules.is_empty() or i >= list.size() or not is_instance_valid(c3d):
		return out
	if c3d.camera == null or not c3d.camera.current or c3d.clickable == null:
		return out
	var id := String(list[i].step)
	var cmd: int = 210 + flight.STEP_IDS.find(id)
	var parts := []
	for e in c3d.clickable._controls:
		if int(e[1].get("click", [-1])[0]) == cmd:
			parts.append(e)
	if parts.is_empty() and id == "engine":  # the F-16's engine step: the throttle out of OFF
		parts = c3d.clickable._controls.filter(func(e): return int(e[1].get("click", [-1])[0]) == 5)
	if not parts.is_empty():
		out.append(_mark(parts, String(list[i][lang()]), c3d.camera))
	var g: Dictionary = data.get("gauges", {}).get(_family(), {}).get(id, {})
	var gauge := c3d.find_child(String(g.get("node", "-")), true, false) as Node3D
	if gauge != null:
		var meshes := [gauge] if gauge is MeshInstance3D else gauge.find_children("*", "MeshInstance3D", true, false)
		var mi: Node = meshes.front() if not meshes.is_empty() else null
		if mi != null:
			out.append(_mark([[mi, {"ring": float(g.get("radius_m", 0.0))}]], String(g.label[lang()]), c3d.camera))
	return out


## One mark around parts `parts` ([mesh, its record]): a ring on the screen (canvas px), or a pointer at the screen's
## edge toward them when out of the view.
func _mark(parts: Array, text: String, cam: Camera3D) -> Dictionary:
	var k: float = flight.ui.scale.x
	var vp_size := cam.get_viewport().get_visible_rect().size
	var to_canvas := func(p: Vector3) -> Vector2:
		return cam.unproject_position(p) / vp_size * flight.get_viewport().get_visible_rect().size / k
	var lo := Vector2(INF, INF)
	var hi := -lo
	var behind := false
	var centre := Vector3.ZERO
	for e in parts:
		var mi: MeshInstance3D = e[0]
		var box := mi.get_aabb()
		var c: Vector3 = mi.global_transform * box.get_center()
		centre += c / parts.size()
		var r := float(e[1].get("ring", 0.0))
		var pts := []
		if r > 0.0:
			var side := cam.global_transform.basis.x * r
			var up := cam.global_transform.basis.y * r
			pts = [c - side - up, c + side + up]
		else:
			for j in 8:
				pts.append(mi.global_transform * box.get_endpoint(j))
		for p in pts:
			behind = behind or cam.is_position_behind(p)
			var sp: Vector2 = to_canvas.call(p)
			lo = lo.min(sp)
			hi = hi.max(sp)
	var view: Vector2 = flight.ui.size
	var mid := (lo + hi) / 2.0
	if not behind and Rect2(Vector2.ZERO, view).has_point(mid):
		var rad := maxf(hi.x - lo.x, hi.y - lo.y) / 2.0 + RING_PAD
		return {"rect": Rect2(mid - Vector2(rad, rad), Vector2(rad, rad) * 2.0), "text": text, "at": mid}
	# Out of the view: toward the part as the eye sees it (its bearing in the camera's frame, which holds behind the
	# eye too), held at the screen's edge.
	var local: Vector3 = cam.global_transform.affine_inverse() * centre
	var d := Vector2(local.x, -local.y)
	d = d.normalized() if d.length() > 0.0001 else Vector2.DOWN
	var half := view / 2.0 - Vector2(150, 40)
	var t := minf(half.x / maxf(absf(d.x), 0.001), half.y / maxf(absf(d.y), 0.001))
	return {"rect": null, "text": text, "at": view / 2.0 + d * t, "dir": d}


func _draw_marks() -> void:
	var font: Font = flight.ui.get_theme_default_font()
	var taken := []  # the pointers' chips drawn: a later one steps clear of them
	for m in marks:
		if m.rect != null:
			var r: Rect2 = m.rect
			var c := r.get_center()
			var rad := r.size.x / 2.0
			_overlay.draw_arc(c, rad, 0, TAU, 64, Color(RING, 0.25), 14.0, true)
			_overlay.draw_arc(c, rad + 3.5, 0, TAU, 64, Color(NAVY, 0.6), 3.0, true)
			_overlay.draw_arc(c, rad, 0, TAU, 64, RING, 4.0, true)
			if String(m.text) != "" and m.text != _step_text():
				_tag(font, Vector2(r.position.x - 10, c.y) if not he() else Vector2(r.end.x + 10, c.y), m.text, true)
		else:
			var d: Vector2 = m.dir
			var arrow: String = (
				"▼"
				if absf(d.y) >= absf(d.x) and d.y > 0
				else "▲" if absf(d.y) >= absf(d.x) else "▶" if d.x > 0 else "◀"
			)
			var at: Vector2 = m.at
			var step := Vector2(0, 32 if at.y < _overlay.size.y / 2.0 else -32)
			while taken.any(func(t): return absf(t.y - at.y) < 30.0 and absf(t.x - at.x) < 300.0):
				at += step
			taken.append(at)
			_tag(font, at, "%s %s" % [arrow, m.text], false)


func _step_text() -> String:
	var list := checklist()
	var i := _current()
	return String(list[i][lang()]) if i < list.size() else ""


## A label on the navy chip: beside a ring (`beside`: ending at `at`, inline-start of it), or centred at `at`.
func _tag(font: Font, at: Vector2, text: String, beside: bool) -> void:
	var px := 16
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + 16.0
	var h := 26.0
	var x := at.x - w / 2.0
	if beside:
		x = at.x - w if not he() else at.x
	var r := Rect2(x, at.y - h / 2.0, w, h)
	var box := StyleBoxFlat.new()
	box.bg_color = NAVY
	box.border_color = RING
	box.set_border_width_all(2 if not beside else 1)
	box.set_corner_radius_all(5)
	_overlay.draw_style_box(box, r)
	_overlay.draw_string(
		font, Vector2(r.position.x + 8, r.position.y + 19), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Look.TEXT
	)
