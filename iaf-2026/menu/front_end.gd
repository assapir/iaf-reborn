# Modern IAF's front end (iaf-2026/docs/front-end.md): Home, Pick a plane, Training, Pick a mission, Preferences, the
# Debrief, the Pilot log and Attributions, one screen per step in the frame of the round-3 design (where you are and
# the pilot at the top, key hints and the screen's buttons at the bottom). Hebrew mirrors every screen: the root's
# layout direction is right to left, so containers, anchors, sliders, toggles and radio lists flip; the jet photos
# never flip. The main scene (main.tscn) and, over a frozen flight, the pause menu and the Preferences
# (Settings.front_end_overlay: terrain_view.gd sets `flight` and `screen`).
extends Control

const Look := preload("res://menu/look.gd")
const Fly := preload("res://flight/fly.gd")
const Wizard := preload("res://setup/wizard.gd")
const SoundBuses := preload("res://shared/audio/sound_buses.gd")
const KeysScreen := preload("res://menu/keys_screen.gd")
const JoystickScreen := preload("res://menu/joystick_screen.gd")
const Scenery := preload("res://shared/terrain/scenery.gd")

const PHOTOS := "res://data/photos"
## The canvas the screens lay out on: the window shows it scaled to its height (Look's sizes are its pixels).
const CANVAS := Vector2i(1920, 1080)
## The planes the sim flies, each from its home base (strings <name>, base_<base>).
const JETS := [
	{"unit": "f16i", "airframe": "f16i", "name": "sufa", "code": "F-16I", "base": "ramon", "seats": 2},
	{"unit": "f16d", "airframe": "f16", "name": "barak", "code": "F-16D", "base": "ramat_david", "seats": 2},
	{"unit": "f35i", "airframe": "f35i", "name": "adir", "code": "F-35I", "base": "nevatim", "seats": 1},
]
## Each jet's photos (data/photos): [in the air or its card, on the ground (the Training card and the briefing)].
const JET_PHOTOS := {
	"sufa": ["sufa.jpg", "sufa_ground.jpg"], "barak": ["barak.jpg", "barak.jpg"], "adir": ["adir.jpg", "adir.jpg"]
}
## Each photo's credit in the footer (data/photos/SOURCES.md): [English author, Hebrew author, licence].
const PHOTO_CREDITS := {
	"sufa.jpg": ["Major Ofer, Israeli Air Force", "רס״ן עופר, חיל האוויר", "CC BY 4.0"],
	"sufa_ground.jpg": ["MathKnight and Zachi Evenor", "MathKnight וזכי אבנור", "CC BY 4.0"],
	"barak.jpg": ["Zachi Evenor and MathKnight", "זכי אבנור ו־MathKnight", "CC BY 2.0"],
	"adir.jpg": ["Major Ofer, Israeli Air Force", "רס״ן עופר, חיל האוויר", "CC BY 4.0"],
}
## The Preferences: [group, [[setting, control, choices]]]. Controls: "dropdown" / "radio" ([[label key, value]]; a
## label without a string is shown as written), "switch" (choices: [off value, on value], default [false, true]),
## "slider" (0..1), "page" (a button that opens that screen: keys_screen → keys). Realism and aids have no switch
## (plan.md "physics"; sim_settings.gd PROFILE).
const PREFS := [
	[
		"graphics",
		[
			[
				"antialiasing",
				"dropdown",
				[["MSAA 4×", "msaa4"], ["MSAA 4× + FXAA", "msaa4_fxaa"], ["TAA", "taa"], ["FSR 2", "temporal"]]
			],
			[
				"upscaling",
				"dropdown",
				[["upscaling_off", "off"], ["upscaling_quality", "quality"], ["upscaling_balanced", "balanced"]]
			],
			["shadows", "switch", []],
			["terrain_detail", "slider", []],
			["clouds", "radio", [["clouds_flat", "original"], ["clouds_volumetric", "volumetric"]]],
			["scenery", "radio", [["off", "off"], ["on", "on"], ["scenery_detailed", "detailed"]]],
			["fullscreen", "switch", []],
			["vsync", "switch", []],
		]
	],
	["language", [["language", "dropdown", [["lang_en", "en"], ["lang_he", "he"]]]]],
	[
		"sound",
		[
			["engine_volume", "slider", []],
			["sfx_volume", "slider", []],
			["speech_volume", "slider", []],
			["mute", "switch", []],
		]
	],
	[
		"devices",
		[
			["flight_controls", "radio", [["joystick", 1], ["keyboard", 0]]],
			["rudder", "radio", [["pedals", 1], ["keyboard", 0]]],
			["throttle", "radio", [["lever", 1], ["keyboard", 0]]],
			["stick_response", "radio", [["linear", "linear"], ["soft", "soft"]]],
			["keys_screen", "page", []],
			["joystick_screen", "page", []],
		]
	],
]
## The screen each breadcrumb opens (_header).
const CRUMB_PAGES := {
	"home": "home",
	"plane": "plane",
	"training": "training",
	"preferences": "prefs",
	"devices": "prefs_section",  # the Keys and Joystick screens' crumb: their section
	"pilot_log": "log",
	"credits": "credits"
}
## The screens that show the picked jet: Pick a plane opens in their place before the first pick.
const NEEDS_JET := ["training", "mission"]
## Esc on each screen goes here ("" = nothing on Home).
const BACK := {
	"plane": "home",
	"training": "home",
	"mission": "training",
	"prefs": "home",
	"prefs_section": "prefs",
	"debrief": "home",
	"log": "home",
	"credits": "home",
	"keys": "prefs_section",
	"joystick": "prefs_section",
}

## Over a flight: terrain_view.gd sets these before adding the overlay ("flytsd": the pause menu, "pref").
var flight: Node = null
var screen := ""
var page := ""
var strings := {}
var setup_strings := {}
## The jet's training missions (readable mission files), the one picked, and the debrief record shown.
var missions: Array = []
var mission_i := 0
var record := {}
var record_file := ""
## The Preferences section shown (prefs_section).
var pref_group := ""
var _focus: Control
static var _textures := {}
static var _themes := {}
var _attempts: Array = []
static var _args_done := false


func _ready() -> void:
	if flight != null:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_fit_overlay()
		get_viewport().size_changed.connect(_fit_overlay)
		show_page("prefs" if screen == "pref" else "pause")
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var win := get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	win.content_scale_size = CANVAS
	if not _args_done:
		_args_done = true
		if start_args(OS.get_cmdline_user_args()):
			return
	if Settings.flown_debrief != "":
		var f := Settings.flown_debrief
		Settings.flown_debrief = ""
		if open_debrief(f):
			return
	show_page("home")


## `-- --mission <id>`: flies that mission at once (true when it starts).
func start_args(args: PackedStringArray) -> bool:
	var at := args.find("--mission") + 1
	return at > 0 and at < args.size() and Fly.start(int(args[at]))


func _exit_tree() -> void:
	if flight == null:
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED


## The overlay lays out on the same 1080-high canvas, scaled to the window.
func _fit_overlay() -> void:
	var vp := get_viewport_rect().size
	var k := vp.y / CANVAS.y
	scale = Vector2(k, k)
	position = Vector2.ZERO
	size = vp / k


func s(key: String) -> String:
	return str(strings.get(key, key))


func he() -> bool:
	return Settings.language == "he"


## The picked jet's row of JETS ({} before the first pick).
func jet() -> Dictionary:
	for j in JETS:
		if j.unit == Settings.sim_jet:
			return j
	return {}


# --- the frame --------------------------------------------------------------------------------------------------------


## Builds screen `p` in the current language.
func show_page(p: String) -> void:
	if p in NEEDS_JET and jet().is_empty():
		p = "plane"
	page = p
	var lang := "he" if he() else "en"
	strings = Settings.load_json("res://menu/strings_%s.json" % lang)
	setup_strings = Settings.load_json("res://setup/strings_%s.json" % lang)
	if not _themes.has(he()):
		_themes[he()] = Look.make()
	theme = _themes[he()]
	_attempts = []
	var dir := Control.LAYOUT_DIRECTION_RTL if he() else Control.LAYOUT_DIRECTION_LTR
	# Over a flight the overlay itself stays left to right: a right-to-left control under a CanvasLayer mirrors its own
	# position by its unscaled width (_fit_overlay), which pushed the pause menu off the screen. Its children carry
	# the direction instead (below).
	layout_direction = dir if flight == null else Control.LAYOUT_DIRECTION_LTR
	if flight == null:
		get_window().title = str(setup_strings.get("name", ""))
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_focus = null
	if flight != null:
		var dim := ColorRect.new()
		dim.color = Color(Look.BG, 0.94 if p.begins_with("prefs") or p in ["keys", "joystick"] else 0.7)
		add_child(dim)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		var bg := ColorRect.new()
		bg.color = Look.BG
		add_child(bg)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not jet().is_empty():
		missions = jet_missions(jet().unit)
		mission_i = clampi(mission_i, 0, maxi(missions.size() - 1, 0))
	call("_page_" + p)
	if flight != null:
		for c in get_children():
			c.layout_direction = dir
	if _focus != null:
		_grab.call_deferred(_focus)


## The top bar: the name and where you are (`crumbs`, the last one current), the pilot with the jet.
func _header(crumbs: Array) -> void:
	var shade := _shade(true)
	shade.offset_bottom = 120
	var bar := _margin(self, 67, 0)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 97
	var h := _hbox(bar, 10)
	# The sim's name in the screen's language, two titles (the wizard's strings: "Modern IAF", "הזרוע הארוכה").
	var mark := _label(h, str(setup_strings.get("name", "")), "Mark")
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_spacer_px(h, 0).custom_minimum_size.x = 16
	for i in crumbs.size():
		if i > 0:
			_label(h, "·", "Crumb").size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var t: String = s(crumbs[i]) if strings.has(crumbs[i]) else crumbs[i]
		# Every crumb but the current one opens its screen (a jet's name: its Training).
		var to: String = CRUMB_PAGES.get(crumbs[i], "training")
		var c: Control
		if i == crumbs.size() - 1:
			c = _label(h, t, "CrumbOn")
		else:
			c = _button(h, t, "CrumbLink", show_page.bind(to))
			c.name = "Crumb_" + to
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_spacer(h)
	var who := VBoxContainer.new()
	who.add_theme_constant_override("separation", -4)
	who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(who)
	_label(who, pilot_name(), "Strong")
	var j := jet()
	if not j.is_empty():
		_label(who, "%s · %s" % [s(j.name), s("base_short_" + j.base)], "Muted")
	var av := PanelContainer.new()
	av.add_theme_stylebox_override("panel", Look.box(Look.ACCENT, Look.ACCENT, 0, 26, Vector2.ZERO))
	av.custom_minimum_size = Vector2(52, 52)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(av)
	var ini := _label(av, initials(pilot_name()), "Avatar")
	ini.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ini.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


## The bottom bar: key hints [[key, string]], the photo credit, the screen's buttons.
func _footer(keys: Array, credit := "", actions: Array = []) -> HBoxContainer:
	var shade := _shade(false)
	shade.offset_top = -130
	var bar := _margin(self, 67, 0)
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -97
	var h := _hbox(bar, 40)
	h.name = "Footer"
	for k in keys:
		var hint := _hbox(h, 10)
		hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var kbd := PanelContainer.new()
		var kb := Look.box(Color(0, 0, 0, 0), Color("5a616c"), 1, 5, Vector2(9, 1))
		kb.border_width_bottom = 3
		kbd.add_theme_stylebox_override("panel", kb)
		hint.add_child(kbd)
		_label(kbd, k[0], "Key").text_direction = Control.TEXT_DIRECTION_LTR
		_label(hint, s(k[1]), "Muted")
	_spacer(h)
	if credit != "":
		var c := _label(h, credit, "Small")
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_spacer(h)
	for a in actions:
		h.add_child(a)
		a.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return h


## A fade from the bar's edge so the bars read over a photo.
func _shade(top: bool) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(0.086, 0.094, 0.11, 0.9 if top else 0.92))
	g.set_color(1, Color(0.086, 0.094, 0.11, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0, 0 if top else 1)
	tex.fill_to = Vector2(0, 1 if top else 0)
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	r.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
	return r


## The screen's body between the bars, `inline` px from the sides.
func _body(inline := 96, top := 112, bottom := 112) -> MarginContainer:
	var m := _margin(self, inline, 0)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.offset_top = top
	m.offset_bottom = -bottom
	return m


func _credit(files: Array) -> String:
	var parts := []
	for f in files:
		var c: Array = PHOTO_CREDITS[f]
		var line := "%s, %s" % [c[1] if he() else c[0], c[2]]
		if line not in parts:
			parts.append(line)
	return s("photos" if parts.size() > 1 else "photo") % "; ".join(parts)


# --- Home -------------------------------------------------------------------------------------------------------------


func _page_home() -> void:
	var j := jet()
	# Before the first pick: the first jet's photo, the sim's name and one action, Choose a plane.
	var air: String = JET_PHOTOS[j.name if not j.is_empty() else JETS[0].name][0]
	# The photo on the inline-end two thirds, fading into the background toward the column.
	var ph := _photo(self, air)
	ph.anchor_left = 0.32
	ph.anchor_right = 1.0
	ph.anchor_bottom = 1.0
	ph.offset_left = 0
	ph.offset_right = 0
	var fade := TextureRect.new()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.14, 0.34])
	g.colors = PackedColorArray([Look.BG, Color(Look.BG, 0.6), Color(Look.BG, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	fade.texture = tex
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.flip_h = he()
	ph.add_child(fade)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_header(["home"])
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 39)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(col)
	col.anchor_left = 0.05
	col.anchor_right = 0.39
	col.anchor_top = 0.11
	col.anchor_bottom = 0.9
	col.offset_left = 0
	col.offset_right = 0
	var name_box := _vbox(col, 0)
	if j.is_empty():
		_label(name_box, str(setup_strings.get("name", "")), "Jet").add_theme_font_size_override("font_size", 84)
		var choose := _button(col, s("choose_plane"), "Fly", func(): show_page("plane"))
		choose.name = "ChoosePlane"
		choose.custom_minimum_size = Vector2(258, 86)
		choose.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_focus = choose
	else:
		var code := _label(name_box, j.code, "Code")
		code.text_direction = Control.TEXT_DIRECTION_LTR
		_label(name_box, s(j.name), "Jet")
		_label(name_box, s("base_" + j.base), "Big")
		var fly := _button(col, s("fly"), "Fly", func(): show_page("training"))
		fly.name = "Fly"
		fly.custom_minimum_size = Vector2(258, 86)
		fly.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_focus = fly
	_home_log(col)
	var menu := _vbox(col, 0)
	_rule(menu, Look.LINE)
	var items := [
		["change_plane", func(): show_page("plane")],
		["pilot_log", func(): show_page("log")],
		["preferences", func(): show_page("prefs")],
		["credits", func(): show_page("credits")],
		["quit", func(): Settings.quit()],
	]
	for item in items.slice(1 if j.is_empty() else 0):
		var b := _button(menu, s(item[0]), "Menu", item[1])
		b.name = item[0]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_rule(menu, Look.LINE)
	_footer([["Enter", "select"]], _credit([air]))


## Home's log summary: the flights, the flight time and the last result (none before the first flight).
func _home_log(col: Control) -> void:
	var att := attempts()
	if att.is_empty():
		return
	var log := _vbox(col, 6)
	_label(log, s("pilot_log"), "H3")
	var stats := _hbox(log, 46)
	var total := 0.0
	for a in att:
		total += float(a.get("elapsed_s", 0.0))
	for st in [[str(att.size()), "flights"], [clock(total), "flight_time"]]:
		var one := _hbox(stats, 8)
		var v := _label(one, st[0], "Stat")
		v.text_direction = Control.TEXT_DIRECTION_LTR
		var l := _label(one, s(st[1]), "Muted")
		l.size_flags_vertical = Control.SIZE_SHRINK_END
	var last: Dictionary = att[-1]
	var row := _hbox(log, 16)
	_label(row, s("last") % mission_title(int(last.id)), "Row").size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_chip(row, s("pass" if int(last.result) == 1 else "fail"), int(last.result) == 1)


# --- Pick a plane -----------------------------------------------------------------------------------------------------


func _page_plane() -> void:
	_header(["home", "plane"])
	var v := _vbox(_body(), 30)
	_title(v, s("pick_plane"), "")
	var row := _hbox(v, 40)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var group := ButtonGroup.new()
	var files := []
	for j in JETS:
		var card := Button.new()
		card.name = j.name
		card.theme_type_variation = "Card"
		card.toggle_mode = true
		card.button_group = group
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card.button_pressed = j.unit == Settings.sim_jet
		row.add_child(card)
		var inner := _vbox(card, 0)
		inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		inner.offset_left = 4
		inner.offset_top = 4
		inner.offset_right = -4
		inner.offset_bottom = -4
		var file: String = JET_PHOTOS[j.name][0]
		files.append(file)
		var ph := _photo(inner, file)
		ph.size_flags_vertical = Control.SIZE_EXPAND_FILL
		ph.size_flags_stretch_ratio = 2.1
		if card.button_pressed:
			var bm := _margin(ph, 20, 20)
			bm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			var bh := _hbox(bm, 0)
			bh.alignment = BoxContainer.ALIGNMENT_END
			var badge := PanelContainer.new()
			badge.add_theme_stylebox_override("panel", Look.box(Look.ACCENT, Look.ACCENT, 0, 16, Vector2(16, 3)))
			badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			bh.add_child(badge)
			_label(badge, s("selected"), "Avatar")
		var t := _margin(inner, 33, 26)
		t.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var tv := _vbox(t, 2)
		var code := _label(tv, j.code, "Code")
		code.text_direction = Control.TEXT_DIRECTION_LTR
		_label(tv, s(j.name), "Name")
		_label(tv, s("base_" + j.base), "Big").add_theme_font_size_override("font_size", 27)
		_label(tv, s("seats_%d" % j.seats), "Muted")
		for c in inner.find_children("*", "Control", true, false):
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.pressed.connect(_pick_jet.bind(j))
		if card.button_pressed or _focus == null:
			_focus = card
	var go := _action(s("continue"), "Primary", func(): show_page("training"))
	go.name = "Continue"
	go.disabled = jet().is_empty()
	_footer([["Esc", "back"], ["Enter", "select"]], _credit(files), [go])


func _pick_jet(j: Dictionary) -> void:
	_pick_jet_quiet(j)
	show_page("plane")
	_focus = find_child(j.name, true, false)
	if _focus != null:
		_grab.call_deferred(_focus)


# --- Training (the programme) -----------------------------------------------------------------------------------------


func _page_training() -> void:
	var j := jet()
	_header(["home", j.name])
	var v := _vbox(_body(), 34)
	_title(v, s("fly_jet") % s(j.name), s("base_" + j.base))
	var card := PanelContainer.new()
	card.custom_minimum_size.y = 560
	v.add_child(card)
	var h := _hbox(card, 0)
	var tm := _margin(h, 50, 46)
	tm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := _vbox(tm, 22)
	_label(t, s("training"), "H2").add_theme_font_size_override("font_size", 53)
	_text(t, s("training_text"), "Sub")
	var list := _vbox(t, 0)
	_rule(list, Look.LINE)
	var passed := 0
	for m in missions:
		var row := _hbox(_margin(list, 0, 12), 12)
		_label(row, "%d · %s" % [missions.find(m) + 1, title_of(m)], "Row").size_flags_vertical = (
			Control.SIZE_SHRINK_CENTER
		)
		_spacer(row)
		var st := status(m)
		passed += 1 if st == 1 else 0
		_chip(row, s("not_flown" if st < 0 else ("pass" if st == 1 else "fail")), st == 1)
		_rule(list, Look.LINE)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size.y = 10
	bar.max_value = maxi(missions.size(), 1)
	bar.value = passed
	var pv := _vbox(t, 6)
	pv.add_child(bar)
	_label(pv, s("passed_of") % [passed, missions.size()], "Sub")
	_spacer(t, true)
	var open := _button(t, s("open"), "Primary", func(): show_page("mission"))
	open.name = "Open"
	open.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	open.custom_minimum_size = Vector2(150, 60)
	_focus = open
	var file: String = JET_PHOTOS[j.name][1]
	var ph := _photo(h, file)
	ph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ph.size_flags_stretch_ratio = 0.92
	_footer([["Esc", "back"], ["Enter", "select"]], _credit([file]))


# --- Pick a mission ---------------------------------------------------------------------------------------------------


func _page_mission() -> void:
	var j := jet()
	_header(["home", j.name, "training"])
	var h := _hbox(_body(96, 112, 120), 96)
	var left := _vbox(h, 30)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.73
	_title(left, s("training"), s("base_" + j.base))
	var group := ButtonGroup.new()
	for i in missions.size():
		var m: Dictionary = missions[i]
		var b := Button.new()
		b.name = "Mission%d" % (i + 1)
		b.theme_type_variation = "Card"
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == mission_i
		b.custom_minimum_size.y = 160
		left.add_child(b)
		var row := _hbox(_margin(b, 30, 22), 30)
		row.get_parent().set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var n := _label(row, str(i + 1), "Num")
		n.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var col := _vbox(row, 4)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_label(col, title_of(m), "Strong").add_theme_font_size_override("font_size", 27)
		_label(col, s("desc_" + kind(m)), "Muted")
		var chip_row := _hbox(col, 0)
		var st := status(m)
		var chip_text := s("not_flown") if st < 0 else s("pass" if st == 1 else "fail")
		var best := best_time(m)
		if st == 1 and best > 0:
			chip_text += " · " + clock(best)
		chip_row.add_theme_constant_override("separation", 0)
		var chip := _chip(chip_row, chip_text, st == 1)
		chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		for c in b.find_children("*", "Control", true, false):
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.pressed.connect(_pick_mission.bind(i))
		if i == mission_i:
			_focus = b
	if missions.is_empty():
		return
	var m: Dictionary = missions[mission_i]
	var pane := PanelContainer.new()
	pane.name = "Briefing"
	pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(pane)
	var pv := _vbox(pane, 0)
	var file: String = JET_PHOTOS[j.name][1]
	var ph := _photo(pv, file)
	ph.custom_minimum_size.y = 300
	var b := _vbox(_margin(pv, 38, 34), 22)
	b.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	_label(b, s("mission_n") % [mission_i + 1, s("kind_" + kind(m))], "H3")
	_label(b, title_of(m), "H2")
	var brief := s("brief_" + kind(m))
	if kind(m) == "takeoff":
		brief = brief % str(m.get("runway", ""))
	_text(b, brief, "Row")
	var facts := _hbox(b, 50)
	var budget := s("minutes") % int(float(m.training.get("time_budget_s", 0)) / 60.0)
	var rows := []
	if m.has("runway"):
		rows.append(["runway", str(m.runway)])
	rows.append(["time", str(m.get("time", ""))])
	var wind := int(m.get("wind_kt", 0))
	rows.append(["wind", s("calm") if wind == 0 else s("wind_fmt") % [int(m.get("wind_from", 0)), wind]])
	rows.append(["time_allowed", budget])
	for f in rows:
		var fv := _vbox(facts, 0)
		_label(fv, s(f[0]), "Muted")
		var val := _label(fv, f[1], "Fact")
		if f[0] in ["runway", "time"]:
			val.text_direction = Control.TEXT_DIRECTION_LTR
	var pass_row := _hbox(b, 20)
	var rule := ColorRect.new()
	rule.color = Look.ACCENT
	rule.custom_minimum_size.x = 4
	pass_row.add_child(rule)
	var pt := _vbox(pass_row, 2)
	pt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(pt, s("pass_when"), "Muted")
	var when := s("pass_startup") % budget
	if kind(m) == "takeoff":
		when = s("pass_takeoff") % [int(m.training.get("heading_tolerance_deg", 10)), budget]
	_text(pt, when, "")
	_spacer(b, true)
	var fly := _button(b, s("fly"), "Primary", func(): fly_mission(m))
	fly.name = "Fly"
	fly.custom_minimum_size = Vector2(214, 70)
	fly.add_theme_font_size_override("font_size", 31)
	fly.size_flags_horizontal = Control.SIZE_SHRINK_END
	_footer([["Esc", "back"], ["Enter", "select"]], _credit([file]))


func _pick_mission(i: int) -> void:
	mission_i = i
	show_page("mission")
	_focus = find_child("Mission%d" % (i + 1), true, false)
	if _focus != null:
		_grab.call_deferred(_focus)


## Fly: the mission's flight scene (flight/fly.gd).
func fly_mission(m: Dictionary) -> void:
	Fly.start(int(m.menu_id))


# --- Preferences ------------------------------------------------------------------------------------------------------


## Preferences: the sections, each opening its own screen (_page_prefs_section).
func _page_prefs() -> void:
	if flight == null:
		_header(["home", "preferences"])
	var v := _vbox(_body(96, 112 if flight == null else 60), 30)
	_title(v, s("preferences"), "")
	for g in PREFS:
		var b := Button.new()
		b.name = "Section_" + g[0]
		b.theme_type_variation = "Card"
		b.custom_minimum_size = Vector2(900, 120)
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		v.add_child(b)
		var col := _vbox(_margin(b, 30, 20), 4)
		col.get_parent().set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_label(col, s(g[0]), "Strong").add_theme_font_size_override("font_size", 27)
		var names := []
		for row in g[1]:
			names.append(s(row[0]))
		_label(col, ", ".join(names), "Muted").text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		for c in b.find_children("*", "Control", true, false):
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.pressed.connect(_open_section.bind(g[0]))
		if g[0] == pref_group or _focus == null:
			_focus = b
	_footer([["Esc", "back"], ["Enter", "select"]])


func _open_section(group: String) -> void:
	pref_group = group
	show_page("prefs_section")


## One section of the Preferences (pref_group): its rows, scrolled when they outgrow the screen.
func _page_prefs_section() -> void:
	if flight == null:
		_header(["home", "preferences", pref_group])
	var v := _vbox(_body(96, 112 if flight == null else 60), 30)
	_title(v, s(pref_group), "")
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.x = 1180
	scroll.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	# Room for the scroll bar on either side, so no control sits under it in either direction.
	var bm := _margin(scroll, 32, 0)
	bm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body := _vbox(bm, 0)
	for g in PREFS:
		if g[0] == pref_group:
			for row in g[1]:
				_pref_row(body, row)
	for c in body.find_children("*", "Control", true, false):
		if (c as Control).focus_mode != Control.FOCUS_NONE:
			_focus = c
			break
	_footer([["Esc", "back"], ["Enter", "select"]])


## One preference: its name and note at the inline start, its control at the inline end.
func _pref_row(parent: Control, row: Array) -> void:
	var key: String = row[0]
	var m := _margin(parent, 0, 14)
	m.name = "Pref_" + key
	var h := _hbox(m, 30)
	var t := _vbox(h, 0)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(t, s(key), "Strong").add_theme_font_size_override("font_size", 25)
	if strings.has(key + "_note"):
		_label(t, s(key + "_note"), "Small")
	# Scenery only with setup's scenery step (Scenery.available); greyed without it.
	var off := key == "scenery" and not Scenery.available()
	if off:
		_label(t, s("scenery_missing"), "Small")
		m.modulate.a = 0.5
	var ctl := _hbox(h, 20)
	ctl.custom_minimum_size.x = 420
	ctl.alignment = BoxContainer.ALIGNMENT_END
	ctl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var value = Settings.get(key)
	match row[1]:
		"dropdown":
			var o := OptionButton.new()
			o.name = "Control"
			o.custom_minimum_size = Vector2(307, 58)
			for c in row[2]:
				# A left-to-right mark keeps "MSAA 4×" whole in a right-to-left line.
				o.add_item(s(c[0]) if strings.has(c[0]) else c[0] + "\u200e")
				if c[1] == value:
					o.select(o.item_count - 1)
			o.item_selected.connect(func(i): _set_pref(key, row[2][i][1]))
			ctl.add_child(o)
		"switch":
			var vals: Array = row[2] if not row[2].is_empty() else [false, true]
			var label := _label(ctl, s("on") if value == vals[1] else s("off"), "Row")
			label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var c := CheckButton.new()
			c.name = "Control"
			c.button_pressed = value == vals[1]
			c.toggled.connect(
				func(on):
					label.text = s("on") if on else s("off")
					_set_pref(key, vals[1] if on else vals[0])
			)
			ctl.add_child(c)
		"slider":
			var sl := HSlider.new()
			sl.name = "Control"
			sl.custom_minimum_size = Vector2(283, 30)
			sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			sl.max_value = 1.0
			sl.step = 0.05
			sl.value = float(value)
			ctl.add_child(sl)
			var pct := _label(ctl, "%d%%" % roundi(float(value) * 100), "Row")
			pct.text_direction = Control.TEXT_DIRECTION_LTR
			pct.custom_minimum_size.x = 64
			sl.value_changed.connect(
				func(x):
					pct.text = "%d%%" % roundi(x * 100)
					_set_pref(key, x)
			)
		"page":
			var b := _button(ctl, s("change"), "Secondary", show_page.bind(key.trim_suffix("_screen")))
			b.name = "Control"
		"radio":
			var rv := _vbox(ctl, 4)
			rv.name = "Control"
			var g := ButtonGroup.new()
			for c in row[2]:
				var r := CheckBox.new()
				r.text = s(c[0])
				r.button_group = g
				r.button_pressed = c[1] == value
				r.disabled = (
					off or key == "clouds" and c[1] == "volumetric" and RenderingServer.get_rendering_device() == null
				)
				r.add_theme_font_size_override("font_size", 24)
				r.pressed.connect(_set_pref.bind(key, c[1]))
				rv.add_child(r)
	_rule(parent, Look.LINE)


## Preferences → Devices → Keys and Joystick (iaf-2026/docs/front-end.md §9).
func _page_keys() -> void:
	KeysScreen.page(self)


func _page_joystick() -> void:
	JoystickScreen.page(self)


func _set_pref(key: String, value: Variant) -> void:
	Settings.set(key, value)
	Settings.save()
	if key in ["engine_volume", "sfx_volume", "speech_volume", "mute"]:
		SoundBuses.apply()
	if key == "language":
		# Every string switches at once: the screen again in the new language.
		show_page(page)


# --- Debrief ----------------------------------------------------------------------------------------------------------


## Opens the debrief record `file` (user://debriefs, training.md §4); false when it cannot be read.
func open_debrief(file: String) -> bool:
	var d := Settings.load_json(file)
	if d.is_empty() or not d.has("items"):
		return false
	record = d
	record_file = file
	show_page("debrief")
	return true


func _page_debrief() -> void:
	var m := mission_by_name(str(record.get("mission", "")))
	var j := jet_of(m)
	var bg := _photo(self, str(JET_PHOTOS[j.get("name", "sufa")][0]).replace(".jpg", "_blur.jpg"))
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.modulate = Color(0.55, 0.57, 0.6)
	_header(["training", "debrief"])
	var sheet := PanelContainer.new()
	sheet.name = "Sheet"
	sheet.add_theme_stylebox_override("panel", Look.box(Look.PAPER, Look.PAPER, 0, 5, Vector2.ZERO))
	add_child(sheet)
	sheet.anchor_left = 0.12
	sheet.anchor_right = 0.88
	sheet.anchor_bottom = 1.0
	sheet.offset_left = 0
	sheet.offset_right = 0
	sheet.offset_top = 113
	sheet.offset_bottom = -108
	var v := _vbox(sheet, 0)
	var band := PanelContainer.new()
	var bb := Look.box(Look.NAVY, Look.NAVY, 0, 5, Vector2(33, 12))
	bb.corner_radius_bottom_left = 0
	bb.corner_radius_bottom_right = 0
	band.add_theme_stylebox_override("panel", bb)
	v.add_child(band)
	var bh := _hbox(band, 0)
	_label(bh, s("debrief_band"), "Band")
	_spacer(bh)
	_label(bh, s("number") % ("%04d" % debrief_number()), "Band")
	var inner := _vbox(_margin(v, 33, 22), 0)
	# The fields: Plane flown, From, Time, Mission, Result.
	var fields := _hbox(inner, 0)
	fields.add_theme_constant_override("separation", -1)
	var from := s("base_" + str(j.get("base", "")))
	if m.has("runway"):
		from = s("from_runway") % [from, m.runway]
	var cells := [
		["plane_flown", "%s %s" % [j.get("code", ""), s(j.get("name", ""))], 1.0],
		["from", from, 1.3],
		["f_time", debrief_time(m), 1.3],
		["mission", title_of(m) if not m.is_empty() else str(record.get("mission", "")), 1.1],
		["result", "", 0.7],
	]
	for c in cells:
		var cell := PanelContainer.new()
		cell.add_theme_stylebox_override("panel", Look.box(Color(0, 0, 0, 0), Look.RULE, 1, 0, Vector2(17, 10)))
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.size_flags_stretch_ratio = c[2]
		fields.add_child(cell)
		var cv := _vbox(cell, 2)
		_label(cv, s(c[0]), "PaperLabel")
		if c[0] == "result":
			# The box places a plain Control at the inline start; the stamp inside it keeps its tilt (a container
			# resets its own children's rotation).
			var row := _hbox(cv, 0)
			var tilt := Control.new()
			row.add_child(tilt)
			var stamp := _label(tilt, s("stamp_pass" if record.get("pass", false) else "stamp_fail"), "Stamp")
			stamp.name = "Stamp"
			stamp.add_theme_stylebox_override("normal", Look.box(Color(0, 0, 0, 0), Look.NAVY, 3, 3, Vector2(14, 0)))
			stamp.rotation_degrees = -4.0
			tilt.custom_minimum_size = stamp.get_combined_minimum_size() + Vector2(0, 10)
			stamp.position.y = 6
		else:
			var val := _text(cv, c[1], "PaperValue")
			val.name = "Field_" + c[0]
			if c[0] == "f_time":
				val.text_direction = Control.TEXT_DIRECTION_LTR
	# The mission's goals (the record's `goals`; a record from before them: every number) in two columns.
	var lang := "he" if he() else "en"
	var names: Dictionary = record.get("strings", {}).get(lang, {})
	var all: Array = record.get("items", [])
	var goals: Array = record.get("goals", all.map(func(it): return it.id))
	var shown := []
	for g in goals:
		for it in all:
			if it.id == g and (it.get("value") != null or it.has("text")):
				shown.append(it)
	var half := ceili(shown.size() / 2.0)
	if not shown.is_empty():
		_spacer_px(inner, 22)
		_label(inner, s("numbers"), "PaperHead")
		_rule(inner, Look.INK, 2)
	var cols := _hbox(inner, 62)
	cols.name = "Numbers"
	for c in 2 if not shown.is_empty() else 0:
		var col := _vbox(cols, 0)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for it in shown.slice(c * half, (c + 1) * half):
			var r := _hbox(_margin(col, 0, 9), 12)
			var l := _label(r, str(names.get(it.id, it.id)), "Paper")
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var val := _label(r, value_text(it), "PaperNum")
			val.text_direction = (
				Control.TEXT_DIRECTION_LTR if he() and str(it.unit) in ["deg", ""] else Control.TEXT_DIRECTION_AUTO
			)
			_rule(col, Look.RULE)
	# Remarks: why it failed (the reason that ended it first), or that it passed; the lift-off against the reference.
	_spacer_px(inner, 22)
	_label(inner, s("remarks"), "PaperHead")
	_rule(inner, Look.INK, 2)
	var lines := []
	for r in record.get("reasons", []):
		lines.append(str(names.get(r, r)))
	if record.get("pass", false) and strings.has("done_" + str(record.get("kind", ""))):
		lines.append(s("done_" + str(record.kind)))
	lines.append_array(remarks())
	var rem := _vbox(inner, 0)
	rem.name = "Remarks"
	for i in maxi(lines.size(), 3):
		var l := _label(_margin(rem, 0, 8), lines[i] if i < lines.size() else " ", "Paper")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_rule(rem, Look.RULE)
	var back := _action(s("back_missions"), "Secondary", func(): back_to_missions(m))
	back.name = "BackMissions"
	var again := _action(s("fly_again"), "Primary", func(): fly_mission(m))
	again.name = "FlyAgain"
	again.disabled = m.is_empty()
	_focus = again
	_footer([["Esc", "back"]], "", [back, again])


## The remark the goals give: the lift-off speed against the reference.
func remarks() -> Array:
	var it := {}
	for i in record.get("items", []):
		if i.get("value") != null:
			it[i.id] = i
	if not (it.has("liftoff_speed") and it.has("reference_speed")):
		return []
	var d := float(it.liftoff_speed.value) - float(it.reference_speed.value)
	return [s("remark_above" if d >= 0 else "remark_below") % value_text({"value": absf(d), "unit": "kt"})]


## Back to missions: the flown mission's jet and the mission itself picked.
func back_to_missions(m: Dictionary) -> void:
	var j := jet_of(m)
	if not j.is_empty() and j.unit != Settings.sim_jet:
		_pick_jet_quiet(j)
	var list := jet_missions(Settings.sim_jet)
	mission_i = maxi(list.map(func(x): return x.get("id", "")).find(m.get("id", "")), 0)
	show_page("mission")


func _pick_jet_quiet(j: Dictionary) -> void:
	Settings.sim_jet = j.unit
	Settings.set_jet(j.airframe)
	Settings.save()


## The record's number: its place among the debriefs in the folder, oldest first.
func debrief_number() -> int:
	var files := Array(DirAccess.get_files_at(record_file.get_base_dir())).filter(
		func(f): return f.begins_with("debrief-")
	)
	files.sort()
	return files.find(record_file.get_file()) + 1


## The day and the mission clock from the start to the end: "2 Nov 2026 · 08:00–08:11" (Hebrew "2.11.2026 · …").
func debrief_time(m: Dictionary) -> String:
	var date := str(record.get("date", ""))
	var day := date.get_slice("T", 0).split("-")
	var out := ""
	if day.size() == 3:
		var months: Array = strings.get("months", [])
		if months.is_empty():
			out = "%d.%d.%s" % [int(day[2]), int(day[1]), day[0]]
		else:
			out = "%d %s %s" % [int(day[2]), months[int(day[1]) - 1], day[0]]
	var start := str(m.get("time", ""))
	if start.contains(":"):
		var t0 := int(start.get_slice(":", 0)) * 60 + int(start.get_slice(":", 1))
		var t1 := t0 + int(float(record.get("elapsed_s", 0.0)) / 60.0)
		out += " · %s–%02d:%02d" % [start, (t1 / 60) % 24, t1 % 60]
	return out


## A debrief value with its unit: thousands grouped, seconds as m:ss past a minute; a name (the runway) as it is.
func value_text(it: Dictionary) -> String:
	if it.has("text"):
		return str(it.text)
	var v := float(it.value)
	var unit := str(it.unit)
	if unit == "s" and v >= 60.0:
		return "%s %s" % [clock(v), s("u_min")]
	var num := _group(v)
	match unit:
		"":
			return num
		"deg":
			return num + "°"
		_:
			return "%s %s" % [num, s("u_" + unit) if strings.has("u_" + unit) else unit]


static func _group(v: float) -> String:
	var whole := v == roundf(v)
	var t := str(int(absf(v))) if whole else "%.1f" % absf(v)
	var ip := t.get_slice(".", 0)
	var out := ""
	while ip.length() > 3:
		out = "," + ip.right(3) + out
		ip = ip.left(ip.length() - 3)
	out = ip + out
	if not whole:
		out += "." + t.get_slice(".", 1)
	return ("-" if v < 0 else "") + out


# --- Pilot log --------------------------------------------------------------------------------------------------------


func _page_log() -> void:
	_header(["home", "pilot_log"])
	var v := _vbox(_body(), 26)
	_title(v, s("pilot_log"), "")
	var att := attempts()
	if att.is_empty():
		_label(v, s("no_flights"), "Sub")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := _vbox(scroll, 0)
	list.name = "Log"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not att.is_empty():
		_log_row(list, [s("date"), s("mission"), s("plane_flown")], -1, null)
	for i in range(att.size() - 1, -1, -1):
		var a: Dictionary = att[i]
		var m := mission_by_id(int(a.id))
		var j := jet_of(m)
		var cells := [
			str(a.get("date", "")).replace("T", " ").left(16),
			title_of(m) if not m.is_empty() else str(a.id),
			"%s %s" % [j.get("code", ""), s(j.get("name", ""))],
		]
		var b := _log_row(list, cells, int(a.result), a)
		if _focus == null:
			_focus = b
	_footer([["Esc", "back"], ["Enter", "select"]])


func _log_row(list: Control, cells: Array, result: int, a) -> Control:
	var row: Control
	if a == null:
		row = _margin(list, 20, 8)
	else:
		var b := Button.new()
		b.theme_type_variation = "Menu"
		b.custom_minimum_size.y = 58
		var file := str(a.get("debrief", ""))
		b.disabled = not FileAccess.file_exists(file)
		b.pressed.connect(func(): open_debrief(file))
		list.add_child(b)
		row = _margin(b, 20, 8)
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var h := _hbox(row, 30)
	for i in cells.size():
		var l := _label(h, cells[i], "Muted" if a == null else "Row")
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.size_flags_stretch_ratio = [0.8, 1.4, 1.0][i]
		if i == 0:
			l.text_direction = Control.TEXT_DIRECTION_LTR
	# The result column: a box, so its label or chip sits at the column's inline start in both directions.
	var last := _hbox(h, 0)
	last.custom_minimum_size.x = 140
	if a == null:
		_label(last, s("result"), "Muted")
	else:
		_chip(last, s("pass" if result == 1 else "fail"), result == 1)
	for c in row.find_children("*", "Control", true, false):
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rule(list, Look.LINE)
	return row.get_parent() if a != null else row


# --- Attributions -----------------------------------------------------------------------------------------------------


func _page_credits() -> void:
	_header(["home", "credits"])
	var v := _vbox(_body(), 24)
	_title(v, s("credits"), "")
	var scroll := ScrollContainer.new()
	scroll.name = "Credits"
	scroll.focus_mode = Control.FOCUS_ALL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_focus = scroll
	var list := _vbox(scroll, 18)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for c in Wizard.CREDITS:
		var box := _vbox(list, 4)
		var head := _hbox(box, 16)
		var name := _label(head, c[0], "Strong")
		name.text_direction = Control.TEXT_DIRECTION_LTR
		_label(head, str(setup_strings.get(c[1], "")), "Muted")
		for line in c[2]:
			# The licence lines stay as their licences word them: English, left to right.
			var l := _text(box, line, "Small")
			l.text_direction = Control.TEXT_DIRECTION_LTR
		_rule(list, Look.LINE)
	_footer([["Esc", "back"]])


# --- Over a flight: the pause menu ------------------------------------------------------------------------------------


func _page_pause() -> void:
	# Centred by a container, so it stays centred whatever its labels and the view measure (a preset's offsets are
	# fixed at the size it had then).
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.name = "Pause"
	center.add_child(panel)
	panel.custom_minimum_size = Vector2(560, 0)
	var v := _vbox(_margin(panel, 48, 40), 22)
	_label(v, str(setup_strings.get("name", "")), "Mark")
	_label(v, s("paused"), "H2")
	var go := _button(v, s("resume"), "Primary", func(): flight.close_front_end())
	go.name = "Resume"
	_focus = go
	_button(v, s("preferences"), "Secondary", func(): show_page("prefs")).name = "PausePrefs"
	var end := _button(v, s("end_flight"), "Secondary", func(): flight._end_flight(true))
	end.name = "EndFlight"


# --- keys -------------------------------------------------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
		return
	get_viewport().set_input_as_handled()
	back()


## Esc: the screen before this one; over a flight, back to the flight (the Preferences apply then).
func back() -> void:
	if flight != null:
		if page in ["keys", "joystick"]:
			show_page("prefs_section")
		elif page == "prefs_section":
			show_page("prefs")
		elif page == "prefs" and screen != "pref":
			flight._apply_preferences()
			show_page("pause")
		else:
			flight.close_front_end()
		return
	var to: String = BACK.get(page, "")
	if to != "":
		show_page(to)


# --- data -------------------------------------------------------------------------------------------------------------


## The jet's training missions: the compiled list (iaf-sim missions) read from their readable files
## (res://data/missions), the player's unit `unit`, by menu id.
func jet_missions(unit: String) -> Array:
	var list := Settings.load_json(Settings.converted(Settings.missions_folder().path_join("missionlist.json")))
	var out := []
	for id in list:
		var m := Settings.load_json("res://data/missions/%s.json" % str(list[id][0]))
		if str(m.get("start", {}).get("unit", "")) == unit and m.has("training"):
			out.append(m)
	out.sort_custom(func(a, b): return int(a.menu_id) < int(b.menu_id))
	return out


func mission_by_name(name: String) -> Dictionary:
	return Settings.load_json("res://data/missions/%s.json" % name) if name.is_valid_filename() else {}


func mission_by_id(id: int) -> Dictionary:
	var list := Settings.load_json(Settings.converted(Settings.missions_folder().path_join("missionlist.json")))
	return mission_by_name(str(list[str(id)][0])) if list.has(str(id)) else {}


func mission_title(id: int) -> String:
	var m := mission_by_id(id)
	return title_of(m) if not m.is_empty() else str(id)


func title_of(m: Dictionary) -> String:
	var t: Dictionary = m.get("title", {})
	return str(t.get("he" if he() else "en", t.get("en", "")))


static func kind(m: Dictionary) -> String:
	return str(m.get("training", {}).get("kind", "startup"))


static func jet_of(m: Dictionary) -> Dictionary:
	var unit := str(m.get("start", {}).get("unit", ""))
	for j in JETS:
		if j.unit == unit:
			return j
	return {}


## Every attempt in the pilot log, oldest first: {id, result, debrief, date, elapsed_s (from its debrief)}.
func attempts() -> Array:
	if not _attempts.is_empty():
		return _attempts
	var out := []
	for m in Settings.load_json(Settings.pilot_log_file()).get("missions", []):
		for a in m.get("attempts", []):
			var e: Dictionary = a.duplicate()
			e["id"] = int(m.id)
			e["elapsed_s"] = float(Settings.load_json(str(a.get("debrief", ""))).get("elapsed_s", 0.0))
			out.append(e)
	out.sort_custom(func(a, b): return str(a.get("date", "")) < str(b.get("date", "")))
	_attempts = out
	return out


func _grab(c: Control) -> void:
	if is_instance_valid(c) and c.is_inside_tree():
		c.grab_focus()


## The mission's last result: 1 pass, 0 fail, -1 not flown.
func status(m: Dictionary) -> int:
	var st := -1
	for a in attempts():
		if int(a.id) == int(m.menu_id):
			st = int(a.result)
	return st


## The shortest passing flight of the mission, s (0 = none).
func best_time(m: Dictionary) -> float:
	var best := 0.0
	for a in attempts():
		var t := float(a.elapsed_s)
		if int(a.id) == int(m.menu_id) and int(a.result) == 1 and t > 0 and (best == 0.0 or t < best):
			best = t
	return best


## The pilot's name: the computer's user name (Settings.pilot_name when set: the pictures' sample pilot).
func pilot_name() -> String:
	if Settings.pilot_name != "":
		return Settings.pilot_name
	var user := OS.get_environment("USER")
	if user == "":
		user = OS.get_environment("USERNAME")
	return user.capitalize() if user != "" else "Pilot"


static func initials(name: String) -> String:
	var out := ""
	for w in name.split(" ", false):
		out += w.left(1).to_upper()
	return out.left(2)


## m:ss (h:mm:ss past an hour).
static func clock(sec: float) -> String:
	var t := int(sec)
	if t >= 3600:
		return "%d:%02d:%02d" % [t / 3600, t % 3600 / 60, t % 60]
	return "%d:%02d" % [t / 60, t % 60]


# --- building blocks --------------------------------------------------------------------------------------------------


func _label(parent: Node, t: String, kind_name := "") -> Label:
	var l := Label.new()
	l.text = t
	l.theme_type_variation = kind_name
	parent.add_child(l)
	return l


func _text(parent: Node, t: String, kind_name := "") -> Label:
	var l := _label(parent, t, kind_name)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _title(parent: Node, title: String, sub: String) -> void:
	var v := _vbox(parent, 2)
	_label(v, title, "H1")
	if sub != "":
		_label(v, sub, "Sub")


func _button(parent: Node, t: String, kind_name: String, on: Callable) -> Button:
	var b := _action(t, kind_name, on)
	parent.add_child(b)
	return b


func _action(t: String, kind_name: String, on: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.theme_type_variation = kind_name
	b.pressed.connect(on)
	if kind_name in ["Primary", "Secondary"]:
		b.custom_minimum_size = Vector2(178, 60)
	return b


func _chip(parent: Node, t: String, ok: bool) -> Label:
	var l := _label(parent, t, "ChipOk" if ok else "Chip")
	l.add_theme_stylebox_override(
		"normal", Look.box(Color(0, 0, 0, 0), Look.ACCENT if ok else Look.EDGE, 1, 18, Vector2(16, 3))
	)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


func _photo(parent: Node, file: String) -> TextureRect:
	if not _textures.has(file):
		var img := Image.load_from_file(ProjectSettings.globalize_path(PHOTOS.path_join(file)))
		_textures[file] = ImageTexture.create_from_image(img) if img != null else null
	var r := TextureRect.new()
	r.texture = _textures[file]
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	r.clip_contents = true
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


func _rule(parent: Node, c: Color, px := 1) -> void:
	var r := ColorRect.new()
	r.color = c
	r.custom_minimum_size.y = px
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)


func _margin(parent: Node, x: int, y: int) -> MarginContainer:
	var m := MarginContainer.new()
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, x)
	for side in ["top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, y)
	parent.add_child(m)
	return m


func _hbox(parent: Node, sep: int) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	parent.add_child(h)
	return h


func _vbox(parent: Node, sep: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	parent.add_child(v)
	return v


func _spacer(parent: Node, vertical := false) -> void:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if vertical:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(c)


func _spacer_px(parent: Node, px: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = px
	parent.add_child(c)
	return c
