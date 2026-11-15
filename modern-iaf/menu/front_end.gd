# Modern IAF's front end (modern-iaf/docs/front-end.md): the Hangar, Pick a mission, Preferences, the
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
const SoundTable := preload("res://shared/audio/sound_table.gd")
const KeysScreen := preload("res://menu/keys_screen.gd")
const JoystickScreen := preload("res://menu/joystick_screen.gd")
const PrefChoices := preload("res://shared/util/pref_choices.gd")
const FileExport := preload("res://shared/util/file_export.gd")
const TerrainPreload := preload("res://shared/terrain/terrain_preload.gd")
const Img := preload("res://shared/util/img.gd")
const KeyTable := preload("res://shared/controls/key_table.gd")
const BriefingPage := preload("res://menu/briefing_page.gd")
const LoadoutScreen := preload("res://menu/loadout_screen.gd")
const Turntable := preload("res://shared/aircraft/turntable.gd")
const AircraftModel := preload("res://shared/aircraft/aircraft_model.gd")

const PHOTOS := "res://data/photos"
## The settings file Export offers to write (Settings → footer, FileExport).
const SETTINGS_FILE := "modern-iaf-settings.cfg"
## The start-up steps' switches cropped from each jet's 3D cockpit: <unit>/<step>.webp (tests/_switch_crops.gd).
const SWITCHES := "res://data/switches"
## The canvas the screens lay out on: the window shows it scaled to its height (Look's sizes are its pixels).
const CANVAS := Vector2i(1920, 1080)
## The right-to-left mark (full_name).
const RLM := "\u200f"
## Each Sound slider's sample, a clip of its class from the sim's own sounds (SoundTable: [code, sub code] or a file)
## on that slider's bus: the engine, the master caution tone, a tower call.
const SAMPLES := {
	"engine_volume": [["SFX_START_ENGINE", "None"], SoundBuses.ENGINE],
	"sfx_volume": [["SFX_WARNING", "WRN_MASTER"], SoundBuses.SFX],
	"speech_volume": ["twr_takeoff.wav", SoundBuses.SPEECH],
}
## The planes the sim flies, each from its home base (strings <name>, base_<base>; the squadron: data/airbases).
const JETS := [
	{"unit": "f16i", "airframe": "f16i", "name": "sufa", "code": "F-16I", "base": "ramon", "icao": "llrm"},
	{"unit": "f16d", "airframe": "f16", "name": "barak", "code": "F-16D", "base": "ramat_david", "icao": "llrd"},
	{"unit": "f35i", "airframe": "f35i", "name": "adir", "code": "F-35I", "base": "nevatim", "icao": "llnv"},
]
## The jets shown after them in the Hangar, greyed and not pickable until the sim flies them (the user, 2026-11-10).
const SOON := [
	{"unit": "f15i", "name": "raam", "code": "F-15I", "base": "hatzerim", "icao": "llhb"},
	{"unit": "f15c", "name": "baz", "code": "F-15C", "base": "tel_nof", "icao": "llek"},
]
## Each flyable jet's photo (data/photos): its blurred copy is the debrief's background.
const JET_PHOTOS := {"sufa": "sufa.jpg", "barak": "barak.jpg", "adir": "adir.jpg"}
## The Preferences: [group, [[setting, control, choices]]]. Controls: "dropdown" / "radio" ([[label key, value]]; a
## label without a string is shown as written), "switch" (choices: [off value, on value], default [false, true]),
## "slider" (0..1), "page" (a button that opens that screen: keys_screen → keys). A row reborn shows too has no choices
## here: they come from shared/util/pref_choices.gd (pref_choices), each named by the string "<setting>_<value>", else
## "<value>". Realism and aids have no switch (plan.md "physics"; sim_settings.gd PROFILE).
const PREFS := [
	[
		"graphics",
		[
			["antialiasing", "dropdown"],
			["upscaling", "dropdown"],
			["shadows", "switch", []],
			["shadow_reach", "switch"],
			["terrain_detail", "slider", []],
			["clouds", "radio"],
			["scenery", "radio"],
			["fullscreen", "switch"],
			["vsync", "switch", []],
		]
	],
	["language", [["language", "dropdown"]]],
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
			["throttle_detent", "detent", []],
			["stick_response", "radio", [["linear", "linear"], ["soft", "soft"]]],
			["keys_screen", "page", []],
			["joystick_screen", "page", []],
		]
	],
]
## The screen each breadcrumb opens (_header).
const CRUMB_PAGES := {
	"hangar": "hangar",
	"training": "mission",
	"preferences": "prefs",
	"devices": "prefs",  # the Keys and Joystick screens' crumb: the Preferences on their section
	"pilot_log": "log",
	"pilot": "pilot",
	"pilots": "pilots",
	"credits": "credits"
}
## The screens that show the picked jet: the Hangar opens in their place before the first pick.
const NEEDS_JET := ["mission", "arming"]
## Esc on each screen goes here (the Hangar's: the Quit prompt).
const BACK := {
	"mission": "hangar",
	"arming": "mission",
	"prefs": "hangar",
	"debrief": "hangar",
	"log": "pilot",
	"credits": "hangar",
	"pilot": "hangar",
	"pilots": "pilot",
	"keys": "prefs",
	"joystick": "prefs",
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
var record_sortie := 0
## The Preferences section shown beside the list (_page_prefs).
var pref_group := ""
var _focus: Control
## The Sound sliders' sample player and the sound table it reads (made at the first slider move).
var _sample: AudioStreamPlayer
var _sounds: RefCounted
static var _textures := {}
## The sim's key table for the briefing's keys (KeyTable.load_table, loaded once).
var _keys: RefCounted = null
## The unit records' folder (a test's own records: tests/_loadout_shot.gd's lowered maximum).
var units_dir := "res://data/db/units"
static var _theme: Theme = null
## The records store's view, read once per page: the sorties (Pilot log) and the summary (the Hangar).
var _sorties = null
var _summary = null
## The pilot's profile (IafPilotLog.pilot: name, nickname, picture), read once per page; the pictures' textures.
var _profile = null
static var _pictures := {}
## The Pilot screen's draft, stored by Save: `name`, `nickname` and `picture` (a file just chosen, "" = the stored
## one).
var draft := {}
## The Pilot screen makes a new pilot (New pilot on the pilot list) instead of editing the active one.
var creating := false
static var _args_done := false


func _ready() -> void:
	Input.joy_connection_changed.connect(_on_joy_connection)
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
	if Settings.flown_sortie > 0:
		var id := Settings.flown_sortie
		Settings.flown_sortie = 0
		if open_debrief(id):
			return
	show_page("hangar")


## `-- --mission <id>`: flies that mission at once (true when it starts).
func start_args(args: PackedStringArray) -> bool:
	var at := args.find("--mission") + 1
	return at > 0 and at < args.size() and Fly.start(int(args[at]))


func _exit_tree() -> void:
	if flight == null:
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED


## The overlay lays out on the same 1080-high canvas, scaled to the window.
func _fit_overlay() -> void:
	Look.fit(self, get_viewport_rect().size)
	position = Vector2.ZERO


func s(key: String) -> String:
	return str(strings.get(key, key))


func he() -> bool:
	return Settings.language == "he"


## The jet's squadron at its base ({unit, number, name: {en, he}, source}; {} where the base file names none).
## "846 · 201 Squadron The One · Ramon": the jet's tail number (its unit record's `tail`), its squadron and its base
## (the user, 2026-11-09: the wing is the base, so it is left out).
func subtitle(j: Dictionary, with_tail := true) -> String:
	if j.is_empty():
		return ""
	var parts := []
	var tail := str(Settings.load_json("res://data/db/units/%s.json" % j.unit).get("tail", "")) if with_tail else ""
	if tail != "":
		parts.append(tail)
	var sq := squadron(j)
	if not sq.is_empty():
		parts.append(s("squadron") % [int(sq.number), str(sq.name.get("he" if he() else "en", ""))])
	parts.append(s("base_" + j.base))
	return " · ".join(parts)


func squadron(j: Dictionary) -> Dictionary:
	for sq in Settings.load_json("res://data/airbases/%s.json" % j.icao).get("squadrons", []):
		if sq.get("unit") == j.unit:
			return sq
	return {}


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
		p = "hangar"
	var page_was := page
	page = p
	strings = Settings.strings("res://menu/strings")
	setup_strings = Settings.strings("res://setup/strings")
	if _theme == null:
		_theme = Look.make()
	theme = _theme
	_sorties = null
	_summary = null
	_profile = null
	# No profile yet (the first start): the Pilot screen makes it before the Hangar, or the pilot list when the records
	# hold other pilots (the pictures' sample pilot, Settings.pilot_name, has one).
	if p == "hangar" and flight == null and first_start():
		var others = JSON.parse_string(IafPilotLog.pilots(Settings.records_db()))
		p = "pilots" if others is Array and not others.is_empty() else "pilot"
		page = p
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
	if p != "pilot":
		creating = false
	elif page_was != "pilot":
		var was := {} if creating else profile()
		draft = {"name": str(was.get("name", "")), "nickname": str(was.get("nickname", "")), "picture": ""}
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
		# A crumb: a strings key, a text (a jet's name: the Hangar) or [text, the screen it opens].
		var cr = crumbs[i]
		var t: String = str(cr[0]) if cr is Array else (s(cr) if strings.has(cr) else cr)
		# Every crumb but the current one opens its screen.
		var to: String = str(cr[1]) if cr is Array else CRUMB_PAGES.get(cr, "hangar")
		var c: Control
		if i == crumbs.size() - 1:
			c = _label(h, t, "CrumbOn")
		else:
			c = _button(h, t, "CrumbLink", _crumb.bind(to))
			c.name = "Crumb_" + (to if cr is Array or strings.has(cr) else "jet")
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_spacer(h)
	if page == "pilot" and not creating and first_start():
		return  # the first start: no pilot yet to show
	# The Hangar: the Settings (a gear and the word) before the pilot, who is one button (the nickname, the name
	# under it, the picture) that opens the Pilot screen.
	var block: Button = null
	var host: Control = h
	if page == "hangar":
		var gear := _button(h, s("preferences"), "Secondary", func(): show_page("prefs"))
		gear.name = "Settings"
		gear.icon = Look.gear_icon()
		gear.add_theme_constant_override("h_separation", 10)
		gear.add_theme_font_size_override("font_size", 20)
		gear.custom_minimum_size = Vector2(0, 46)
		gear.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_spacer_px(h, 0).custom_minimum_size.x = 18
		block = _action("", "PilotLink", show_page.bind("pilot"))
		block.name = "PilotBlock"
		block.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(block)
		var m := _margin(block, 12, 6)
		m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		host = _hbox(m, 10)
	var who := VBoxContainer.new()
	who.add_theme_constant_override("separation", -4)
	who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	host.add_child(who)
	var who_name := _label(who, pilot_name(), "Strong")
	who_name.name = "PilotName"
	who_name.size_flags_horizontal = Control.SIZE_SHRINK_END
	var j := jet()
	if page == "hangar":
		# The Hangar: the name under the nickname (the nickname alone when it is the only one).
		var full := str(profile().get("name", ""))
		if Settings.pilot_name == "" and str(profile().get("nickname", "")) != "" and full != "":
			var l := _label(who, full, "Muted")
			l.name = "PilotFullName"
			l.size_flags_horizontal = Control.SIZE_SHRINK_END
	elif not j.is_empty():
		_label(who, "%s · %s" % [full_name(j), subtitle(j)], "Muted")
	# The picture in its 3:4 frame, else the initials in a disc.
	var pic := picture()
	if pic != null:
		_picture_frame(host, Vector2(42, 56), pic).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	else:
		var av := PanelContainer.new()
		av.add_theme_stylebox_override("panel", Look.box(Look.ACCENT, Look.ACCENT, 0, 26, Vector2.ZERO))
		av.custom_minimum_size = Vector2(52, 52)
		av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		host.add_child(av)
		var ini := _label(av, initials(pilot_name()), "Avatar")
		ini.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ini.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if block != null:
		for c in block.find_children("*", "Control", true, false):
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		block.custom_minimum_size = host.get_parent().get_combined_minimum_size()


## The bottom bar: the photo credit and the screen's buttons (none when it has neither); `at_end`: the credit at the
## bar's inline end (right in English, left in Hebrew), smaller; `start`: buttons at the bar's inline start.
func _footer(credit := "", actions: Array = [], at_end := false, start: Array = []) -> void:
	if credit == "" and actions.is_empty() and start.is_empty():
		return
	var shade := _shade(false)
	shade.offset_top = -130
	var bar := _margin(self, 67, 0)
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -97
	var h := _hbox(bar, 40)
	h.name = "Footer"
	for a in start:
		h.add_child(a)
		a.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_spacer(h)
	if credit != "":
		var c := _label(h, credit, "Small")
		c.name = "Credit"
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if at_end:
			c.add_theme_font_size_override("font_size", 16)
		else:
			# A long credit (the plane screen's five photos) wraps instead of pushing the buttons off the screen.
			c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			c.size_flags_stretch_ratio = 8.0
			_spacer(h)
	for a in actions:
		h.add_child(a)
		a.size_flags_vertical = Control.SIZE_SHRINK_CENTER


## A fade from the bar's edge so the bars read over a photo.
func _shade(top: bool) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(Look.BG, 0.9 if top else 0.92))
	g.set_color(1, Color(Look.BG, 0))
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


# --- Hangar -----------------------------------------------------------------------------------------------------------


## The Hangar (front-end.md §1, the user's A25, 2026-11-13): the sim's first screen, in place of Home, Pick a plane and
## the jet's Training page. The jets at the inline start, the picked one turning in 3D in the middle with its full
## name faint behind it, its card at the inline end: the squadron and base, facts, the training's progress, Missions
## and campaign (greyed) and Fly. The jet picked is the one flown or picked last, else the first (no jet unpicked).
func _page_hangar() -> void:
	if jet().is_empty():
		_pick_jet_quiet(JETS[0])
		missions = jet_missions(JETS[0].unit)
	var j := jet()
	# The floor: the roundel blue lit under the jet, fading into the page.
	var floor_g := Gradient.new()
	floor_g.offsets = PackedFloat32Array([0.0, 1.0])
	floor_g.colors = PackedColorArray([Look.RAISED, Look.BG])
	var floor_t := GradientTexture2D.new()
	floor_t.gradient = floor_g
	floor_t.fill = GradientTexture2D.FILL_RADIAL
	floor_t.fill_from = Vector2(0.5, 0.58)
	floor_t.fill_to = Vector2(0.5 + 0.47 / 0.7, 0.58)
	var stage := TextureRect.new()
	stage.texture = floor_t
	stage.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The jet's full name, large and faint, behind the jet.
	var ghost := _label(self, full_name(j).to_upper() if not he() else full_name(j), "Jet")
	ghost.name = "Ghost"
	ghost.add_theme_font_size_override("font_size", 150)
	ghost.add_theme_color_override("font_color", Color(1, 1, 1, 0.045))
	ghost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ghost.clip_text = true
	_place(ghost, 400, 450, 185, 0)
	_jet_view(j)
	_header(["hangar"])
	_rail(j)
	_jet_card(j)
	# The sources and licences, the model's among them (docs/credits.md: the credit lives on Attributions).
	var cr := _button(self, s("credits"), "CrumbLink", func(): show_page("credits"))
	cr.name = "credits"
	cr.add_theme_font_size_override("font_size", 17)
	_place(cr, 60, -1, -66, 0)
	_hangar_focus()


## The Hangar's focus order (F1), by Tab and by the arrows: the top bar (Settings, the pilot), the jets, the jet's view
## (Tab only: with the focus its arrows orbit the jet), Fly, Attributions. Down from the top bar goes to the picked
## jet, Down from the last jet to Attributions; Down from Fly stays (the foot is the list's, not the card's). Without
## missions Fly takes no focus.
func _hangar_focus() -> void:
	var gear: Control = find_child("Settings", true, false)
	var block: Control = find_child("PilotBlock", true, false)
	var jets: Array = find_child("Jets", true, false).get_children().filter(
		func(c): return c is Button and c.focus_mode != Control.FOCUS_NONE
	)
	var picked: Control = jets.filter(func(b): return b.button_pressed).front()
	var fly: Button = find_child("Fly", true, false)
	var cr: Control = find_child("credits", true, false)
	var card: Control = fly if fly.focus_mode != Control.FOCUS_NONE else null
	var view: Control = find_child("Turntable", true, false)
	var views := [view] if view != null and not view.is_queued_for_deletion() else []
	_chain([gear, block] + jets + views + ([card] if card != null else []) + [cr])
	# The sides on the screen: the inline start is the right in Hebrew.
	var start := "right" if he() else "left"
	var end := "left" if he() else "right"
	_nb(gear, {"top": gear, end: block, "bottom": picked})
	_nb(block, {"top": block, start: gear, end: block, "bottom": picked})
	_nb(jets[0], {"top": gear})
	_nb(jets[-1], {"bottom": cr})
	for b in jets:
		_nb(b, {start: b, end: card if card != null else b})
	if card != null:
		_nb(card, {"top": gear, start: picked, end: card, "bottom": card})
	_nb(cr, {"top": jets[-1], start: cr, end: card if card != null else cr, "bottom": cr})


## Tab and Shift + Tab through `controls` in that order, round.
func _chain(controls: Array) -> void:
	for i in controls.size():
		controls[i].focus_next = controls[i].get_path_to(controls[(i + 1) % controls.size()])
		controls[i].focus_previous = controls[i].get_path_to(controls[i - 1])


## Sets `c`'s focus neighbours: {"top" / "bottom" / "left" / "right": the control there}.
func _nb(c: Control, to: Dictionary) -> void:
	for side in to:
		c.set("focus_neighbor_" + side, c.get_path_to(to[side]))


## Places `c` by its edges on the canvas: `start` px from the inline start (-1: none), `end` px from the inline end
## (-1: none), `top` px from the top (negative: from the bottom), `h` its height (0: its own).
func _place(c: Control, start: int, end: int, top: int, h: int) -> void:
	c.anchor_left = 0.0 if start >= 0 else 1.0
	c.anchor_right = 1.0 if end >= 0 else 0.0
	c.anchor_top = 0.0 if top >= 0 else 1.0
	c.anchor_bottom = c.anchor_top
	c.offset_left = start if start >= 0 else -end
	c.offset_right = -end if end >= 0 else start
	c.offset_top = top
	c.offset_bottom = top + (h if h > 0 else c.get_combined_minimum_size().y)
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH if start >= 0 and end >= 0 else Control.GROW_DIRECTION_END


## The jets: the flyable ones, then the ones the sim does not fly yet, greyed, out of reach and without a word on why.
## A click (or Enter) picks a jet; the arrows move between them, then on to the card.
func _rail(j: Dictionary) -> void:
	var rail := _vbox(self, 10)
	rail.name = "Jets"
	_place(rail, 68, -1, 130, 0)
	rail.custom_minimum_size.x = 330
	rail.offset_right = rail.offset_left + 330
	var h3 := _label(rail, s("aircraft").to_upper(), "H3")
	h3.add_theme_font_size_override("font_size", 19)
	_spacer_px(rail, 2)
	var group := ButtonGroup.new()
	for row in JETS + SOON:
		var soon: bool = row in SOON
		var b := Button.new()
		b.name = row.name
		b.theme_type_variation = "JetRow"
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = row.unit == j.unit
		b.custom_minimum_size.y = 90
		b.disabled = soon
		if soon:
			b.focus_mode = Control.FOCUS_NONE
			b.modulate = Color(1, 1, 1, 0.42)
		rail.add_child(b)
		var v := _vbox(_margin(b, 20, 12), 0)
		v.get_parent().set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_label(v, full_name(row), "JetName")
		_label(v, "%s · %s" % [s("squadron_n") % int(squadron(row).get("number", 0)), s("base_" + row.base)], "Small")
		for c in b.find_children("*", "Control", true, false):
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not soon:
			b.pressed.connect(_hangar_pick.bind(row))


## A jet picked in the Hangar: stored (the F-16 switch too) and the screen shown again with it, the focus kept on it.
func _hangar_pick(j: Dictionary) -> void:
	if j.unit == Settings.sim_jet:
		return
	_pick_jet_quiet(j)
	show_page("hangar")
	_focus = find_child(j.name, true, false)
	_grab.call_deferred(_focus)


## The jet turning in the middle (shared/aircraft/turntable.gd) with its stores: the pilot's loadout for it, else its
## unit record's (the missions' own). A still picture of it (data/hangar/<unit>.webp) when the model does not load or
## its converted descriptor is missing (no model load tried then).
func _jet_view(j: Dictionary) -> void:
	Settings.set_jet(j.airframe)  # the F-16 switch picks the Sufa's or the Barak's model
	var plane := str(
		Settings.load_json("res://shared/extra/planes/%s/airframe.json" % j.airframe).get("base", j.airframe)
	)
	# The model only when its descriptor is there: a fresh install before setup has none of the converted planes.
	if not AircraftModel.load_descriptor(plane).is_empty():
		var tt: TextureRect = Turntable.new()
		tt.name = "Turntable"
		add_child(tt)
		_place(tt, 380, 470, 250, 800)
		if tt.show_jet(plane, jet_stores(j)):
			return
		tt.queue_free()
	var still := TextureRect.new()
	still.name = "Still"
	still.texture = Img.load_texture(ProjectSettings.globalize_path("res://data/hangar/%s.webp" % j.unit))
	still.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	still.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	still.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(still)
	_place(still, 380, 470, 250, 800)


## The jet's stores for the turntable: {pylon 0..8 (A..I): {path, count, lugged, bomb}} from loadout `lo` (JSON
## text, "" the unit record's; null: the pilot's now, as the Loadout screen shows it; IafBriefing.arming; each slot's
## `pylon` maps the real station number to the engine's pylon, the F-35I's 5 to D).
func jet_stores(j: Dictionary, lo = null) -> Dictionary:
	var m := {"start": {"unit": j.unit}}
	var out := {}
	var slots: Dictionary = arming(m, _arm_now(m) if lo == null else str(lo)).get("slots", {})
	for st in slots:
		var w := Settings.load_json("res://data/db/weapons/%s.json" % str(slots[st].id))
		if str(w.get("model", "")) == "":
			continue
		var k := str(w.get("kind", ""))
		if slots[st].get("pylon") == null:
			continue
		out[int(slots[st].pylon)] = {
			"path": str(w.model), "count": int(slots[st].count), "lugged": k in ["bomb", "tank"], "bomb": k == "bomb"
		}
	return out


## The picked jet's card: its name, squadron and base, its facts, the training's progress, Missions and campaign
## (greyed until the sim has them, no text on why) and Fly, which opens the training's missions and briefing.
func _jet_card(j: Dictionary) -> void:
	var card := PanelContainer.new()
	card.name = "JetCard"
	add_child(card)
	_place(card, -1, 68, 130, 0)
	card.offset_left = -68 - 420
	card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var v := _vbox(_margin(card, 32, 30), 18)
	var name := _label(v, full_name(j), "Name")
	name.name = "JetTitle"
	name.add_theme_font_size_override("font_size", 64 if (j.code + s(j.name)).length() <= 9 else 58)
	# This jet's own data, the same three for every jet (the user, A31): its squadron (a long name wraps), its base
	# and its tail number.
	var facts := _vbox(v, 14)
	facts.name = "Facts"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	var all := jet_facts(j)
	for f in all:
		var cell := _vbox(facts if f == all[0] else row, 0)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_label(cell, f[0], "Small").add_theme_font_size_override("font_size", 16)
		var val := _text(cell, f[1], "Fact")
		val.add_theme_font_size_override("font_size", 28)
	facts.add_child(row)
	# The training: passed of all, the bar, the last flight on this jet.
	var tbox := PanelContainer.new()
	tbox.name = "Training"
	tbox.add_theme_stylebox_override("panel", Look.box(Color(0, 0, 0, 0), Look.LINE, 1, 6, Vector2(16, 14)))
	v.add_child(tbox)
	var tv := _vbox(tbox, 8)
	if missions.is_empty():
		# No missions (the sim's data not built): what is missing and the setup command, in place of the progress.
		_setup_note(tv)
	var th := _hbox(tv, 10)
	th.visible = not missions.is_empty()
	_label(th, s("training"), "Strong")
	_spacer(th)
	var passed := 0
	for m in missions:
		passed += 1 if status(m) == 1 else 0
	_label(th, s("passed_of") % [passed, missions.size()], "Small").size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size.y = 8
	bar.max_value = maxi(missions.size(), 1)
	bar.value = passed
	tv.add_child(bar)
	bar.visible = th.visible
	var last := _label(tv, last_flight(), "Small")
	last.name = "LastFlight"
	last.visible = th.visible
	var camp := _soon(v, s("campaign"), "Secondary")
	camp.name = "Campaign"
	camp.tooltip_text = ""
	camp.custom_minimum_size.y = 56
	camp.modulate = Color(1, 1, 1, 0.45)
	var go := _button(v, s("fly"), "Fly", func(): show_page("mission"))
	go.name = "Fly"
	go.custom_minimum_size.y = 76
	_focus = go
	if missions.is_empty():
		# Disabled, drawn dim (its plain box, as Missions and campaign) and out of the focus: the picked jet takes it.
		go.disabled = true
		go.focus_mode = Control.FOCUS_NONE
		go.add_theme_stylebox_override("disabled", go.get_theme_stylebox("normal"))
		go.modulate = Color(1, 1, 1, 0.45)
		_focus = find_child(j.name, true, false)


## The jet's own data: [label, value] for its squadron (its airbase file's), its base and its tail number (its unit
## record's, the number painted on its model).
func jet_facts(j: Dictionary) -> Array:
	var sq := squadron(j)
	var tail := str(Settings.load_json("res://data/db/units/%s.json" % j.unit).get("tail", ""))
	return [
		[
			s("squadron_l"),
			"%d %s" % [int(sq.get("number", 0)), str(sq.get("name", {}).get("he" if he() else "en", ""))]
		],
		[s("base_l"), s("base_" + j.base)],
		[s("tail_number"), tail],
	]


## The last flight on the picked jet (its `missions`): "Last: Take-off · Pass · 13 Nov 2026", or that none was flown.
func last_flight() -> String:
	var ids := missions.map(func(m): return int(m.menu_id))
	for i in range(sorties().size() - 1, -1, -1):
		var a: Dictionary = sorties()[i]
		if int(a.mission_id) in ids:
			var r := s("pass" if int(a.result) == 1 else "fail")
			return s("last_flight") % [mission_title(int(a.mission_id)), r, day_text(str(a.date))]
	return s("not_flown")


## What is missing without the sim's data and the command that builds it (./modern-iaf-setup; Windows: its .ps1) on a
## line of its own, left to right in both languages, at the inline start.
func _setup_note(parent: Control) -> VBoxContainer:
	var v := _vbox(parent, 6)
	v.name = "NoMissions"
	_text(v, s("no_missions"), "Row")
	var cmd := _label(v, ".\\modern-iaf-setup.ps1" if OS.get_name() == "Windows" else "./modern-iaf-setup", "Strong")
	cmd.name = "SetupCommand"
	cmd.text_direction = Control.TEXT_DIRECTION_LTR
	cmd.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT  # mirrored by the layout: the right in Hebrew
	return v


## "F-16I Sufa" / "F-16I סופה": the jet's code and name, everywhere the jet is named (the user, A25).
## In Hebrew a right-to-left mark leads: a Label takes its paragraph's direction from the first strong letter, and the
## Latin code would make the line left to right, the code read last ("סופה F-16I"; the user, A31).
func full_name(j: Dictionary) -> String:
	if j.is_empty():
		return ""
	return "%s%s %s" % [RLM if he() else "", j.code, s(j.name)]


# --- Pick a mission ---------------------------------------------------------------------------------------------------


func _page_mission() -> void:
	var j := jet()
	if missions.is_empty():
		_header(["hangar", full_name(j), "training"])
		var left := _vbox(_body(96, 112, 120), 30)
		_title(left, s("training"), subtitle(j))
		_setup_note(left).custom_minimum_size.x = 900
		_focus = find_child("Crumb_hangar", true, false)
		return
	var m: Dictionary = missions[mission_i]
	_header(["hangar", full_name(j), "training", title_of(m)])
	BriefingPage.build(self, m)


## The picked mission's Loadout screen (front-end.md §10.1, loadout_screen.gd), opened by the briefing's Edit.
func _page_arming() -> void:
	if missions.is_empty():
		show_page("mission")
		return
	LoadoutScreen.page(self)


## A store's name in a slot or the inventory: its short one where the full one runs long ("GBU-31" for "GBU-31 JDAM",
## "370 gal tank"), else the full one; the full one is the tooltip.
func short_store(id: String) -> String:
	return s("short_" + id) if strings.has("short_" + id) else s("store_" + id)


## The unit's Arming figures (IafBriefing.arming of its record with the loadout `lo`, JSON text; "" the record's
## default): {stores, slots, loadout, fuel_kg, tank_fuel_kg, takeoff_kg, over, allowed, inventory, …}.
func arming(m: Dictionary, lo := "") -> Dictionary:
	var a = JSON.parse_string(
		IafBriefing.arming(_unit_file(m), ProjectSettings.globalize_path("res://data/db/weapons"), lo)
	)
	return a if a is Dictionary else {}


## The mission's unit record, an absolute path (in `units_dir`).
func _unit_file(m: Dictionary) -> String:
	return ProjectSettings.globalize_path(units_dir.path_join("%s.json" % str(m.get("start", {}).get("unit", ""))))


## The loadout mission `m` flies with: the pilot's for its jet, "" (the record's) where the mission fixes it.
func mission_loadout(m: Dictionary) -> String:
	return "" if bool(m.get("fixed_loadout", false)) else _arm_now(m)


## The pilot's loadout for the mission's jet now (JSON text; "" the record's default).
func _arm_now(m: Dictionary) -> String:
	return IafPilotLog.loadout(Settings.records_db(), Settings.pilot(), str(jet_of(m).get("unit", "")))


## "16,069": kilograms with a thousands separator.
static func kg_text(v) -> String:
	return Look.group(int(v))


## "0800": the mission's HH:MM as military time.
static func military_time(hhmm: String) -> String:
	return hhmm.replace(":", "")


## "250° / 8": the wind as pilots read it, direction and speed (its unit beside it, `kt`), from the mission's
## wind_from and wind_kt ("000° / 0" when calm).
func wind_text(m: Dictionary) -> String:
	return Look.wind(m)


## A fact's value: its figures left to right (a label of their own, so "16,069 / 23,582" keeps its order inside a
## Hebrew line) and its unit beside them at the inline end ("ק״ג" to their left in Hebrew).
func _fact(parent: Control, figures: String, unit: String) -> HBoxContainer:
	var h := _hbox(parent, 7)
	h.name = "Fact"
	_label(h, figures, "Fact").text_direction = Control.TEXT_DIRECTION_LTR
	if unit != "":
		_label(h, unit, "Fact")
	return h


## The objectives: what the scorer judges (training.md §3), in the rules' figures.
func objectives(m: Dictionary, budget: String) -> Array:
	var out := []
	if kind(m) == "takeoff":
		out.append(s("obj_runway") % _ltr(str(m.get("runway", ""))))
		out.append(s("obj_climb") % int(m.training.get("heading_tolerance_deg", 10)))
	else:
		out.append_array([s("obj_idle"), s("obj_avionics")])
	out.append_array([s("obj_within") % budget, s("obj_safe")])
	return out


## IafBriefing's map of mission `m` at `aspect` (width / height), with `ground` the theatre's ground colour as
## `texture`: {} when it cannot be made (the error logged).
func briefing_map(m: Dictionary, aspect: float, ground := false) -> Dictionary:
	var d = JSON.parse_string(
		IafBriefing.map(
			ProjectSettings.globalize_path("res://data/missions/%s.json" % str(m.get("id", ""))),
			ProjectSettings.globalize_path("res://data/airbases"),
			ProjectSettings.globalize_path(Settings.converted("own/cockpits/%s/map.json" % jet_of(m).get("unit", ""))),
			ProjectSettings.globalize_path(Settings.converted("terrain/israel")),
			aspect
		)
	)
	if not d is Dictionary or d.has("error"):
		push_warning("briefing map: %s" % (d.error if d is Dictionary else "no answer"))
		return {}
	if ground:
		# The theatre's ground colour under the area, about a texel a screen pixel.
		var g: Dictionary = IafBriefing.ground(
			ProjectSettings.globalize_path(Settings.converted("terrain/israel")), PackedFloat64Array(d.extent), 1600
		)
		if not g.is_empty():
			d.texture = ImageTexture.create_from_image(
				Image.create_from_data(g.w, g.h, false, Image.FORMAT_RGB8, g.rgb)
			)
	return d


## "25R · 246°": the runway end and its grid heading (IafBriefing: the HUD's and the compass's), left to right.
func runway_text(runway: String, heading) -> String:
	return runway if heading == null else s("runway_heading") % [runway, roundi(float(heading))]


## Key record `record` of the sim's key table as bound ("⌘" for Ctrl, "Option" for Alt on macOS).
func key_name(record: int) -> String:
	if _keys == null:
		_keys = KeyTable.load_table()
	return _keys.record_key_name(record, Settings.key_bindings)


## A key name or a designator kept whole and left to right inside a Hebrew line.
static func _ltr(t: String) -> String:
	return "\u2066%s\u2069" % t.replace(" ", "\u00a0")


## A key cap (flight_ui.gd's), nothing for "".
func _keycap(parent: Control, key: String) -> Control:
	if key == "":
		var none := Control.new()
		parent.add_child(none)
		return none
	var cap := PanelContainer.new()
	parent.add_child(cap)
	var kb := Look.box(Color(Look.BG, 0.7), Look.DIM, 1, 5, Vector2(9, 1))
	kb.border_width_bottom = 3
	cap.add_theme_stylebox_override("panel", kb)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cap.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var l := _label(cap, key, "Key")
	l.text_direction = Control.TEXT_DIRECTION_LTR
	return cap


func _pick_mission(i: int) -> void:
	mission_i = i
	show_page("mission")
	_focus = find_child("Mission%d" % (i + 1), true, false)
	if _focus != null:
		_grab.call_deferred(_focus)


## Fly: the mission's flight scene (flight/fly.gd), with the ground preloaded on this page (_preload_ground).
func fly_mission(m: Dictionary) -> void:
	if Fly.prepare(int(m.menu_id)):
		TerrainPreload.fly(get_tree())
	else:
		Fly.start(int(m.menu_id))  # the crash page says what is missing


func _process(_delta: float) -> void:
	_preload_ground()


## While the mission page is open, the ground around the picked mission's start and its models load in the background
## (reborn's preload, shared/terrain/terrain_preload.gd) so Fly starts at once; another mission re-aims it, leaving the
## page stops it and drops what it loaded.
var _preload := Vector2i(-1, -1)


func _preload_ground() -> void:
	var id := -1
	if page in ["mission", "arming"] and flight == null and mission_i < missions.size():
		id = int(missions[mission_i].menu_id)
	_preload = TerrainPreload.follow(get_tree(), _preload, Vector2i(id, Settings.player_flight), Fly.prepare)


# --- Preferences ------------------------------------------------------------------------------------------------------


## Preferences: the sections listed at the inline start, the picked one's rows beside them on the same screen
## (pref_group; the first section until one is picked), its pane scrolled over its full height.
func _page_prefs() -> void:
	if flight == null:
		_header(["hangar", "preferences"])
	if PREFS.all(func(g): return g[0] != pref_group):
		pref_group = PREFS[0][0]
	var v := _vbox(_body(96, 112 if flight == null else 60), 30)
	_title(v, s("preferences"), "")
	var h := _hbox(v, 64)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var nav := _vbox(h, 4)
	nav.custom_minimum_size.x = 384
	var group := ButtonGroup.new()
	for g in PREFS:
		var tab := Button.new()
		tab.name = "Section_" + g[0]
		tab.text = s(g[0])
		tab.theme_type_variation = "Tab"
		tab.toggle_mode = true
		tab.button_group = group
		tab.alignment = HORIZONTAL_ALIGNMENT_LEFT
		tab.button_pressed = g[0] == pref_group
		tab.pressed.connect(_open_section.bind(g[0]))
		nav.add_child(tab)
		if g[0] == pref_group:
			_focus = tab
	var scroll := ScrollContainer.new()
	scroll.name = "SectionPane"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.x = 1180
	scroll.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_child(scroll)
	# Room for the scroll bar on either side, so no control sits under it in either direction.
	var bm := _margin(scroll, 32, 0)
	bm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body := _vbox(bm, 0)
	for g in PREFS:
		if g[0] == pref_group:
			for row in g[1]:
				_pref_row(body, row)
	# The settings to / from a file (FileExport, reborn's Extras Settings file); over the flight the pause menu's own.
	if flight == null:
		var exp := _action(
			s("export_settings"), "Secondary", FileExport.settings_file.bind(self, true, SETTINGS_FILE, {}, Callable())
		)
		exp.name = "ExportSettings"
		var imp := _action(
			s("import_settings"),
			"Secondary",
			FileExport.settings_file.bind(self, false, SETTINGS_FILE, {}, import_settings)
		)
		imp.name = "ImportSettings"
		_footer("", [], false, [exp, imp])


## Reads the settings file at `path` (FileExport.import_settings: the sim's own rules, Hebrew without its font in
## English), then the sound levels and the screen again (its language too). The pilot flying and the jet picked stay
## this computer's (the pilot is a row of its records database).
func import_settings(path: String) -> void:
	var who := [Settings.pilot_id, Settings.sim_jet]
	if not FileExport.import_settings(path):
		return
	if who != [Settings.pilot_id, Settings.sim_jet]:
		Settings.pilot_id = who[0]
		Settings.sim_jet = who[1]
		Settings.save()
	SoundBuses.apply()
	show_page(page)


func _open_section(group: String) -> void:
	pref_group = group
	show_page("prefs")


## One preference: its name at the inline start (a line why when it is greyed), its control at the inline end.
func _pref_row(parent: Control, row: Array) -> void:
	var key: String = row[0]
	var m := _margin(parent, 0, 14)
	m.name = "Pref_" + key
	var h := _hbox(m, 30)
	var t := _vbox(h, 0)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(t, s(key), "Strong").add_theme_font_size_override("font_size", 25)
	# Greyed with its why: Scenery without setup's scenery step (PrefChoices.state), the Joystick
	# screen with no joystick connected (it comes alive when one is plugged in, _on_joy_connection).
	var why := ""
	var choices := pref_choices(row)
	if key == "scenery" and not PrefChoices.state(key, "on").available:
		# Left out in setup (modern-iaf/docs/setup.md: the choice file), or not built yet.
		var left: Dictionary = Settings.load_json(Settings.converted("modern-iaf/setup.json"))
		why = "scenery_left_out" if "sim-scenery" in left.get("excluded", []) else "scenery_missing"
	elif key in ["joystick_screen", "throttle_detent"] and Joystick.device() < 0:
		why = "joy_none"
	elif key == "throttle_detent":
		why = "detent_note"
	var off := why != "" and why != "detent_note"
	if why != "":
		_label(t, s(why), "Small")
	if off:
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
			for c in choices:
				# A left-to-right mark keeps "MSAA 4×" whole in a right-to-left line.
				o.add_item(s(c[0]) if strings.has(c[0]) else c[0] + "\u200e")
				o.set_item_disabled(o.item_count - 1, not PrefChoices.state(key, c[1]).available)
				if c[1] == value:
					o.select(o.item_count - 1)
			o.item_selected.connect(func(i): _set_pref(key, choices[i][1]))
			ctl.add_child(o)
		"switch":
			var vals: Array = choices.map(func(c): return c[1]) if not choices.is_empty() else [false, true]
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
		"detent":
			# Ours, reborn's Devices "Detent = MIL" (joystick.gd detent_map): the lever's raw position in its click, past
			# it the afterburner; Off = the lever linear.
			var at := _label(ctl, s("off") if int(value) < 0 else s("detent_at") % int(value), "Row")
			at.name = "Value"
			at.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var no := _button(ctl, s("off"), "Secondary", _set_detent.bind(-1))
			no.name = "Off"
			no.disabled = off or int(value) < 0
			var lever := _button(ctl, s("set_at_lever"), "Secondary", _set_detent.bind(0))
			lever.name = "Control"
			lever.disabled = off
		"page":
			var b := _button(ctl, s("change"), "Secondary", show_page.bind(key.trim_suffix("_screen")))
			b.name = "Control"
			b.disabled = off
		"radio":
			var rv := _vbox(ctl, 4)
			rv.name = "Control"
			var g := ButtonGroup.new()
			for c in choices:
				var r := CheckBox.new()
				r.text = s(c[0])
				r.button_group = g
				r.button_pressed = c[1] == value
				r.disabled = off or not PrefChoices.state(key, c[1]).available
				r.add_theme_font_size_override("font_size", 24)
				r.pressed.connect(_set_pref.bind(key, c[1]))
				rv.add_child(r)
	_rule(parent, Look.LINE)


## A row's [[label, value], ...]: its own, or for a row reborn shows too the shared choices (PrefChoices.CHOICES), each
## labelled by the string "<setting>_<value>", else "<value>", else the choice's own name (the temporal upscaler's by
## the machine: MetalFX on a Mac, PrefChoices.state).
func pref_choices(row: Array) -> Array:
	if row.size() > 2:
		return row[2]
	var key: String = row[0]
	var out := []
	for c in PrefChoices.CHOICES.get(key, []):
		var label := "%s_%s" % [key, c[1]]
		if not strings.has(label):
			label = str(c[1]) if strings.has(str(c[1])) else String(c[0])
		var name: String = PrefChoices.state(key, c[1]).name
		out.append([name if name != "" else label, c[1]])
	return out


## A joystick plugged in or out: the Devices section again, its Joystick row greyed or alive.
func _on_joy_connection(_device: int, _connected: bool) -> void:
	if page == "prefs" and pref_group == "devices":
		show_page.call_deferred("prefs")


## Preferences → Devices → Keys and Joystick (modern-iaf/docs/front-end.md §9).
func _page_keys() -> void:
	KeysScreen.page(self)


func _page_joystick() -> void:
	JoystickScreen.page(self)


## The Keys and Joystick screens' Back (as Esc): the Preferences on Devices.
func back_button() -> Button:
	var b := _action(s("back"), "Secondary", back)
	b.name = "Back"
	return b


## The afterburner detent by the 1998 game's Devices rule (Joystick.detent_choice), then the row again.
func _set_detent(off_or_lever: int) -> void:
	_set_pref("throttle_detent", Joystick.detent_choice(off_or_lever >= 0))
	show_page("prefs")


func _set_pref(key: String, value: Variant) -> void:
	Settings.set(key, value)
	Settings.save()
	if key in ["engine_volume", "sfx_volume", "speech_volume", "mute"]:
		SoundBuses.apply()
	if SAMPLES.has(key):
		play_sample(key)
	if key == "language":
		# Every string switches at once: the screen again in the new language.
		show_page(page)


## A Sound slider moved: its sample at the new level (its bus' volume). A sample already playing keeps on and
## follows the slider; another slider's starts in its place.
func play_sample(key: String) -> void:
	if _sounds == null:
		_sounds = SoundTable.load_table()
	var spec: Array = SAMPLES[key]
	var clip = spec[0]
	var st: AudioStream = _sounds.stream_file(clip) if clip is String else _sounds.stream(_sounds.row(clip[0], clip[1]))
	if st == null:
		return
	if not is_instance_valid(_sample):
		_sample = AudioStreamPlayer.new()
		_sample.name = "Sample"
		add_child(_sample)
	if _sample.playing and _sample.stream == st:
		return
	_sample.stream = st
	_sample.bus = spec[1]
	_sample.play()


# --- Pilot ------------------------------------------------------------------------------------------------------------


## The Pilot screen (the Hangar → the pilot's name): the picture in a service ID photo's fixed 3:4 frame, the name and
## the nickname (the one every screen's top bar shows). The edits are a draft: Save stores them in the records
## (IafPilotLog) and opens the Hangar; Back leaves them, after a prompt when something changed.
func _page_pilot() -> void:
	var first := not creating and first_start()
	_header(["pilot"] if first else ["hangar", "pilot"])
	var v := _vbox(_body(), 30)
	if first:
		_title(v, s("first_pilot"), s("first_pilot_sub"))
	else:
		_title(v, s("new_pilot") if creating else s("pilot"), "")
	var h := _hbox(v, 72)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var col := _vbox(h, 20)
	var fr := _picture_frame(col, Vector2(330, 440), draft_picture())
	fr.name = "Picture"
	# The picture (or its placeholder) opens the file picker as the button does.
	fr.mouse_filter = Control.MOUSE_FILTER_STOP
	fr.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	fr.tooltip_text = s("choose_picture")
	fr.gui_input.connect(_picture_click)
	if draft_picture() == null:
		# No picture: the initials as the name is typed, a head and shoulders before there is a name.
		var empty := TextureRect.new()
		empty.name = "Placeholder"
		empty.texture = Look.person_icon(326)
		empty.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		empty.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fr.add_child(empty)
		var ini := _label(fr, "", "Jet")
		ini.name = "Initials"
		ini.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ini.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ini.add_theme_color_override("font_color", Look.MUTED)
		_show_initials()
	var pick := _button(col, s("choose_picture"), "Secondary", choose_picture)
	pick.name = "ChoosePicture"
	var f := _vbox(h, 12)
	f.custom_minimum_size.x = 640
	for field in ["name", "nickname"]:
		_label(f, s("pilot_" + field), "Strong").add_theme_font_size_override("font_size", 25)
		var e := LineEdit.new()
		e.name = "Field_" + field
		e.text = str(draft.get(field, ""))
		# A hint, never the name: the name in grey read as the field's own text, which no click could edit.
		e.placeholder_text = s("pilot_%s_hint" % field)
		e.max_length = 40
		e.custom_minimum_size = Vector2(640, 58)
		e.text_changed.connect(_edit.bind(field))
		e.gui_input.connect(_field_keys.bind(e))
		f.add_child(e)
		if _focus == null:
			_focus = e
		_spacer_px(f, 12)
	_logbook(h, creating or first)
	var back := _action(s("back"), "Secondary", pilot_back)
	back.name = "Back"
	var save := _action(s("save"), "Primary", save_pilot)
	save.name = "Save"
	save.disabled = str(draft.name).strip_edges() == ""
	var actions := [save] if first else [back, save]
	if not first and not creating:
		var reset := _action(s("reset_log"), "Secondary", reset_log)
		reset.name = "ResetLog"
		reset.disabled = sorties().is_empty()
		var del := _action(s("delete_profile"), "Secondary", delete_profile)
		del.name = "DeleteProfile"
		var other := _action(s("other_pilots"), "Secondary", pilot_back.bind("pilots"))
		other.name = "OtherPilots"
		actions = [reset, del, other, back, save]
	_footer("", actions)
	# Tab: the picture, the fields, the Pilot log, the bottom bar, the crumb.
	var order := [pick] + ["Field_name", "Field_nickname", "pilot_log"].map(func(n): return find_child(n, true, false))
	_chain((order + actions + [find_child("Crumb_hangar", true, false)]).filter(func(c): return c != null))


func _picture_click(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		choose_picture()


## The logbook beside the profile, a panel down to the bottom bar: per plane flown (most hours first) its flight time
## and flights, and per mission its passes and fails (IafPilotLog.logbook). A pilot being made (`new`) has none yet:
## the same panel with "No flights yet." and no Pilot log.
func _logbook(parent: Control, new := false) -> void:
	var panel := PanelContainer.new()
	panel.name = "Logbook"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", Look.box(Look.PANEL, Look.LINE, 1, 6, Vector2(28, 24)))
	parent.add_child(panel)
	var book := _vbox(panel, 10)
	var top := _hbox(book, 16)
	top.custom_minimum_size.y = 60
	var caption := _label(top, s("logbook"), "Strong")
	caption.add_theme_font_size_override("font_size", 25)
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_spacer(top)
	if new:
		_rule(book, Look.LINE)
		_label(book, s("no_flights"), "Sub")
		return
	# The Pilot log (every flight, each opening its debrief): reached from here only.
	_button(top, s("pilot_log"), "Secondary", pilot_back.bind("log")).name = "pilot_log"
	var units := {}
	var list := Settings.load_json(Settings.converted(Settings.missions_folder().path_join("missionlist.json")))
	for id in list:
		units[id] = str(mission_by_name(str(list[id][0])).get("start", {}).get("unit", ""))
	var planes = JSON.parse_string(IafPilotLog.logbook(Settings.records_db(), Settings.pilot(), JSON.stringify(units)))
	if not planes is Array or planes.is_empty():
		_rule(book, Look.LINE)
		_label(book, s("no_flights"), "Sub")
		return
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	book.add_child(scroll)
	var rows := _vbox(scroll, 6)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for pl in planes:
		_rule(rows, Look.LINE)
		var j := {}
		for x in JETS:
			if x.unit == str(pl.plane):
				j = x
		var head := _hbox(rows, 16)
		head.name = "Plane_" + str(pl.plane)
		var name := _label(head, full_name(j) if not j.is_empty() else str(pl.plane), "Strong")
		name.add_theme_font_size_override("font_size", 25)
		_spacer(head)
		var t := _label(head, clock(float(pl.time_s)), "Strong")
		t.text_direction = Control.TEXT_DIRECTION_LTR
		_label(head, s("flight_time"), "Muted")
		_label(rows, s("logbook_flights") % [int(pl.flights), int(pl.passes), int(pl.fails)], "Muted")
		for m in pl.missions:
			var r := _hbox(rows, 12)
			var mm := mission_by_id(int(m.mission_id))
			var title := _label(r, title_of(mm) if not mm.is_empty() else str(m.mission), "Row")
			title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			title.clip_text = true
			_chip(r, s("passes_n") % int(m.passes), true)
			_chip(r, s("fails_n") % int(m.fails), false)


## A field typed in: the draft, the initials in the empty picture, and Save only with a name.
func _edit(t: String, field: String) -> void:
	draft[field] = t
	_show_initials()
	var save: Button = find_child("Save", true, false)
	if save != null:
		save.disabled = str(draft.name).strip_edges() == ""


## The empty picture: the draft name's initials, else the head and shoulders.
func _show_initials() -> void:
	var ini: Label = find_child("Initials", true, false)
	if ini == null:
		return
	ini.text = initials(str(draft.name))
	(find_child("Placeholder", true, false) as Control).visible = ini.text == ""


## Up / Down (ui_up / ui_down, the gamepad's too) move between Name and Nickname, from Nickname down to Save once it
## can save, and from Name up to Choose a picture (a gamepad has no Tab; a LineEdit keeps the arrows otherwise).
func _field_keys(event: InputEvent, e: LineEdit) -> void:
	var to: Control = null
	if event.is_action_pressed("ui_down"):
		to = find_child("Field_nickname" if e.name == "Field_name" else "Save", true, false)
	elif event.is_action_pressed("ui_up"):
		to = find_child("Field_name" if e.name == "Field_nickname" else "ChoosePicture", true, false)
	if to == null:
		return
	e.accept_event()
	if not (to is Button and to.disabled):
		to.grab_focus()


## True when the draft differs from the stored profile (a new pilot's: empty).
func pilot_changed() -> bool:
	var was := {} if creating else profile()
	for k in ["name", "nickname"]:
		if str(draft.get(k, "")).strip_edges() != str(was.get(k, "")):
			return true
	return str(draft.get("picture", "")) != ""


## Save: the draft into the records, then the Hangar.
func save_pilot() -> void:
	if str(draft.name).strip_edges() == "":
		return
	var db := Settings.records_db()
	if creating:
		var id: int = IafPilotLog.add_pilot(db, str(draft.name).strip_edges(), str(draft.nickname).strip_edges())
		if id <= 0:
			return
		use_pilot(id)
	else:
		IafPilotLog.set_pilot(db, Settings.pilot(), str(draft.name).strip_edges(), str(draft.nickname).strip_edges())
	if draft.picture != "":
		_pictures.erase(IafPilotLog.set_picture(db, Settings.pilot(), draft.picture))
	show_page("hangar")


## Reset: the pilot's flights and debriefs deleted after a warning and a second confirm (the profile stays).
func reset_log() -> void:
	var sure := func(): modal(s("reset_sure_title"), s("reset_sure_text"), s("reset"), _reset_now)
	modal(s("reset_title"), s("reset_text") % pilot_name(), s("reset"), sure)


func _reset_now() -> void:
	IafPilotLog.reset(Settings.records_db(), Settings.pilot())
	show_page(page)


## Delete profile: the pilot with its flights, debriefs and picture deleted after a warning and a second confirm; then
## the pilot list, or Create your pilot when no other pilot is left.
func delete_profile() -> void:
	var sure := func(): modal(s("delete_sure_title"), s("delete_sure_text"), s("delete"), _delete_now)
	modal(s("delete_title"), s("delete_text") % pilot_name(), s("delete"), sure)


func _delete_now() -> void:
	var db := Settings.records_db()
	if not IafPilotLog.delete_pilot(db, Settings.pilot()):
		return
	_pictures.erase(str(profile().get("picture", "")))
	draft = {"name": "", "nickname": "", "picture": ""}
	var others = JSON.parse_string(IafPilotLog.pilots(db))
	show_page("pilots" if others is Array and not others.is_empty() else "pilot")


## A breadcrumb: its screen; from the Pilot screen through Back's discard prompt.
func _crumb(to: String) -> void:
	if page == "pilot":
		pilot_back(to)
	else:
		show_page(to)


## Back (and Esc): the Hangar (a new pilot: the pilot list), or screen `to`, after a prompt to discard the changes when
## there are any.
func pilot_back(to := "") -> void:
	if not creating and first_start():
		return  # the first start: Save is the way on
	if to == "":
		to = "pilots" if creating else "hangar"
	if pilot_changed():
		modal(s("discard_title"), s("discard_text"), s("discard"), show_page.bind(to), s("keep_editing"))
	else:
		show_page(to)


## The pilot list (the Pilot screen's Change pilot): every pilot with a name, the active one marked; a click makes
## that pilot the active one (Settings.pilot_id, kept in settings.cfg) and opens the Hangar. New pilot opens an empty
## Pilot screen.
func _page_pilots() -> void:
	_header(["hangar", "pilot", "pilots"])
	var v := _vbox(_body(), 26)
	_title(v, s("pilots"), "")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := _vbox(scroll, 0)
	list.name = "Pilots"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var all = JSON.parse_string(IafPilotLog.pilots(Settings.records_db()))
	for p in all if all is Array else []:
		var b := Button.new()
		b.name = "Pilot_%d" % int(p.id)
		b.theme_type_variation = "Menu"
		b.pressed.connect(use_pilot.bind(int(p.id), true))
		list.add_child(b)
		var row := _hbox(_margin(b, 20, 10), 24)
		row.get_parent().set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var tex := _texture(str(p.picture))
		var fr := _picture_frame(row, Vector2(48, 64), tex)
		if tex == null:
			var ini := _label(fr, initials(str(p.name)), "Avatar")
			ini.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			ini.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			ini.add_theme_color_override("font_color", Look.MUTED)
		var names := _vbox(row, 0)
		names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_label(names, str(p.nickname) if str(p.nickname) != "" else str(p.name), "Row")
		if str(p.nickname) != "":
			_label(names, str(p.name), "Muted")
		if int(p.id) == Settings.pilot():
			_chip(row, s("current"), true)
			_focus = b
		for c in b.find_children("*", "Control", true, false):
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.custom_minimum_size.y = row.get_parent().get_combined_minimum_size().y
		_rule(list, Look.LINE)
	var back := _action(s("back"), "Secondary", show_page.bind("pilot"))
	back.name = "Back"
	var add := _action(s("new_pilot"), "Primary", new_pilot)
	add.name = "NewPilot"
	_footer("", [back, add])


## The pilot `id` as the active one, kept in the settings; `home`: then the Hangar.
func use_pilot(id: int, home := false) -> void:
	Settings.pilot_id = id
	Settings.save()
	if home:
		show_page("hangar")


## True when the active pilot has no profile yet (no name stored) and no sample pilot is set: the first start.
func first_start() -> bool:
	return Settings.pilot_name == "" and str(profile().get("name", "")) == ""


## New pilot: the Pilot screen, empty, making a pilot on Save.
func new_pilot() -> void:
	creating = true
	show_page("pilot")


## Choose a picture: the system's file dialog where there is one (FileExport.dialog).
func choose_picture() -> void:
	var d := FileExport.dialog(self, false, "*.png, *.jpg, *.jpeg, *.webp ; " + s("pictures"), "", set_picture)
	d.name = "PictureDialog"


## The file at `path` as the draft's picture (copied beside the records on Save), then the screen again. False when
## it is no picture.
func set_picture(path: String) -> bool:
	if path.get_extension().to_lower() not in ["png", "jpg", "jpeg", "webp"] or Image.load_from_file(path) == null:
		return false
	draft.picture = path
	_pictures.erase(path)
	show_page(page)
	return true


## The draft's picture: the one just chosen, else the stored one; null without one.
func draft_picture() -> Texture2D:
	return _texture(str(draft.get("picture", ""))) if str(draft.get("picture", "")) != "" else picture()


## A modal over the screen: `title`, `text`, a button that closes it (Cancel, or `no`; focused, also Esc) and the
## button `ok` that closes it and runs `on_ok`.
func modal(title: String, text: String, ok: String, on_ok: Callable, no := "") -> void:
	var dim := ColorRect.new()
	dim.name = "Modal"
	dim.color = Color(Look.BG, 0.8)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	dim.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 0)
	center.add_child(panel)
	var v := _vbox(_margin(panel, 48, 40), 22)
	_label(v, title, "H2")
	if text != "":
		_text(v, text, "Row")
	var h := _hbox(v, 20)
	_spacer(h)
	var cancel := _button(h, no if no != "" else s("cancel"), "Secondary", close_modal)
	cancel.name = "ModalCancel"
	var go := _button(
		h,
		ok,
		"Primary",
		func():
			close_modal()
			on_ok.call()
	)
	go.name = "ModalOk"
	_grab.call_deferred(cancel)


## Closes the modal (Cancel, Esc); false when none is open.
func close_modal() -> bool:
	var m := get_node_or_null("Modal")
	if m == null:
		return false
	remove_child(m)
	m.queue_free()
	return true


## The pilot's profile ({name, nickname, picture}; empty strings before the Pilot screen).
func profile() -> Dictionary:
	if _profile == null:
		var d = JSON.parse_string(IafPilotLog.pilot(Settings.records_db(), Settings.pilot()))
		_profile = d if d is Dictionary else {}
	return _profile


## The pilot's picture, null without one.
func picture() -> Texture2D:
	return _texture(str(profile().get("picture", "")))


## The picture file at `path` as a texture (read once), null for "" or a file that is no picture.
func _texture(path: String) -> Texture2D:
	if path == "":
		return null
	if not _pictures.has(path):
		_pictures[path] = Img.load_texture(path)
	return _pictures[path]


## A service ID photo's frame of `size` (3:4): the picture cropped to fill it, square corners, a thin edge.
func _picture_frame(parent: Node, size: Vector2, tex: Texture2D) -> PanelContainer:
	var fr := PanelContainer.new()
	fr.add_theme_stylebox_override("panel", Look.box(Look.PANEL, Look.EDGE, 1, 0, Vector2(2, 2)))
	fr.custom_minimum_size = size
	fr.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	fr.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	parent.add_child(fr)
	if tex != null:
		var r := TextureRect.new()
		r.texture = tex
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		r.clip_contents = true
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fr.add_child(r)
	return fr


# --- Debrief ----------------------------------------------------------------------------------------------------------


## Opens the debrief record of sortie `id` (the records database, training.md §4); false when it has none.
func open_debrief(id: int) -> bool:
	var d = JSON.parse_string(IafPilotLog.debrief(Settings.records_db(), id))
	if not d is Dictionary or not d.has("items"):
		return false
	record = d
	record_sortie = id
	show_page("debrief")
	return true


func _page_debrief() -> void:
	var m := mission_by_name(str(record.get("mission", "")))
	var j := jet_of(m)
	var bg := _photo(self, str(JET_PHOTOS[j.get("name", "sufa")]).replace(".jpg", "_blur.jpg"))
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.modulate = Color(0.55, 0.57, 0.6)
	_header(["hangar", full_name(j), "training", "debrief"])
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
	_label(bh, s("number") % ("%04d" % record_sortie), "Band")
	var inner := _vbox(_margin(v, 33, 22), 0)
	# The fields: Plane flown, From, Time, Mission, Result.
	var fields := _hbox(inner, 0)
	fields.add_theme_constant_override("separation", -1)
	var from := s("base_" + str(j.get("base", "")))
	if m.has("runway"):
		from = s("from_runway") % [from, m.runway]
	var cells := [
		["plane_flown", full_name(j), 1.0],
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
	var again := _action(s("fly_again"), "Primary", func(): fly_again(m))
	again.name = "FlyAgain"
	again.disabled = m.is_empty()
	_focus = again
	# The flight's recording (the record's `flight`, sim_flight.gd _finish) saved where the player picks (FileExport,
	# reborn's debrief Export flight data); greyed and skipped by the focus when the file is gone.
	var flight_file := str(record.get("flight", ""))
	var export := _action(s("export_flight"), "Secondary", FileExport.export_flight.bind(self, flight_file))
	export.name = "ExportFlight"
	if not FileAccess.file_exists(flight_file):
		export.disabled = true
		export.focus_mode = Control.FOCUS_NONE
		export.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN
		# Its kind's plain box, the text greyed (as _soon: the theme gives the disabled state no box).
		export.add_theme_stylebox_override("disabled", _theme.get_stylebox("normal", "Secondary"))
	_footer("", [back, again], false, [export])


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


## Fly again: the flown mission's briefing as picked from the list (its jet, the Briefing page), Fly focused.
func fly_again(m: Dictionary) -> void:
	back_to_missions(m)
	_focus = find_child("Fly", true, false)
	if _focus != null:
		_grab.call_deferred(_focus)


func _pick_jet_quiet(j: Dictionary) -> void:
	Settings.sim_jet = j.unit
	Settings.set_jet(j.airframe)
	Settings.save()


## The day and the mission clock from the start to the end: "2 Nov 2026 · 08:00–08:11" (Hebrew "2.11.2026 · …").
func debrief_time(m: Dictionary) -> String:
	var out := day_text(str(record.get("date", "")))
	var start := str(m.get("time", ""))
	if start.contains(":"):
		var t0 := int(start.get_slice(":", 0)) * 60 + int(start.get_slice(":", 1))
		var t1 := t0 + int(float(record.get("elapsed_s", 0.0)) / 60.0)
		out += " · %s–%02d:%02d" % [start, (t1 / 60) % 24, t1 % 60]
	return out


## The day of a record's date ("2026-11-02T08:14…"): "2 Nov 2026" (Hebrew "2.11.2026"), "" without one.
func day_text(date: String) -> String:
	var day := date.get_slice("T", 0).split("-")
	if day.size() != 3:
		return ""
	var months: Array = strings.get("months", [])
	if months.is_empty():
		return "%d.%d.%s" % [int(day[2]), int(day[1]), day[0]]
	return "%d %s %s" % [int(day[2]), months[int(day[1]) - 1], day[0]]


## A debrief value with its unit: thousands grouped, seconds as m:ss past a minute; a name (the runway) as it is.
func value_text(it: Dictionary) -> String:
	if it.has("text"):
		return str(it.text)
	var v := float(it.value)
	var unit := str(it.unit)
	if unit == "s" and v >= 60.0:
		return "%s %s" % [clock(v), s("u_min")]
	var num := Look.group(v)
	match unit:
		"":
			return num
		"deg":
			return num + "°"
		_:
			return "%s %s" % [num, s("u_" + unit) if strings.has("u_" + unit) else unit]


# --- Pilot log --------------------------------------------------------------------------------------------------------


func _page_log() -> void:
	_header(["hangar", "pilot", "pilot_log"])
	var v := _vbox(_body(), 26)
	_title(v, s("pilot_log"), "")
	var att := sorties()
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
		var m := mission_by_id(int(a.mission_id))
		var j := jet_of(m)
		var cells := [
			str(a.date).replace("T", " ").left(16),
			title_of(m) if not m.is_empty() else str(a.mission_id),
			full_name(j),
		]
		var b := _log_row(list, cells, int(a.result), a)
		if _focus == null:
			_focus = b


func _log_row(list: Control, cells: Array, result: int, a) -> Control:
	var row: Control
	if a == null:
		row = _margin(list, 20, 8)
	else:
		var b := Button.new()
		b.theme_type_variation = "Menu"
		b.custom_minimum_size.y = 58
		var id := int(a.id)
		b.disabled = not a.has_debrief
		b.pressed.connect(func(): open_debrief(id))
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
	_header(["hangar", "credits"])
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
	for c in Wizard.credits():
		var box := _vbox(list, 4)
		var head := _hbox(box, 16)
		var name := _label(head, c.name, "Strong")
		name.text_direction = Control.TEXT_DIRECTION_LTR
		_label(head, str(setup_strings.get(c.use, "")), "Muted")
		for line in c.lines:
			# The licence lines stay as their licences word them: English, left to right.
			var l := _text(box, line, "Small")
			l.text_direction = Control.TEXT_DIRECTION_LTR
		_rule(list, Look.LINE)


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


## Esc: a picked slot left as it was, a modal closed, else the screen before (back).
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
		return
	get_viewport().set_input_as_handled()
	if close_modal():
		return
	var lo_screen := get_node_or_null("Loadout")
	if lo_screen != null and lo_screen.escape():
		return
	back()


## Esc: the screen before this one; over a flight, back to the flight (the Preferences apply then).
func back() -> void:
	if flight != null:
		if page in ["keys", "joystick"]:
			show_page("prefs")
		elif page == "prefs" and screen != "pref":
			flight._apply_preferences()
			show_page("pause")
		else:
			flight.close_front_end()
		return
	if page == "pilot":
		pilot_back()
		return
	if page == "hangar":
		modal(s("quit_q"), "", s("quit"), func(): Settings.quit())
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


## The pilot's sorties, oldest first (IafPilotLog.sorties: {id, mission_id, mission, date, result, elapsed_s,
## has_debrief}).
func sorties() -> Array:
	if _sorties == null:
		var a = JSON.parse_string(IafPilotLog.sorties(Settings.records_db(), Settings.pilot()))
		_sorties = a if a is Array else []
	return _sorties


## The pilot log's summary (IafPilotLog.summary: flights, flight_time_s, last, missions by menu id).
func summary() -> Dictionary:
	if _summary == null:
		var d = JSON.parse_string(IafPilotLog.summary(Settings.records_db(), Settings.pilot()))
		_summary = d if d is Dictionary else {}
	return _summary


func _grab(c: Control) -> void:
	if is_instance_valid(c) and c.is_inside_tree():
		c.grab_focus()


## The mission's last result: 1 pass, 0 fail, -1 not flown.
func status(m: Dictionary) -> int:
	return int(summary().get("missions", {}).get(str(int(m.menu_id)), {}).get("status", -1))


## The shortest passing flight of the mission, s (0 = none).
func best_time(m: Dictionary) -> float:
	return float(summary().get("missions", {}).get(str(int(m.menu_id)), {}).get("best_s", 0.0))


## The pilot's name as every screen shows it: the nickname, else the name (the Pilot screen), else the computer's user
## name (Settings.pilot_name when set: the pictures' sample pilot).
func pilot_name() -> String:
	if Settings.pilot_name != "":
		return Settings.pilot_name
	for k in ["nickname", "name"]:
		if str(profile().get(k, "")) != "":
			return str(profile()[k])
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


## The side list of a long page (Keys, Joystick): a tab's click scrolls `scroll` to its part (`heads`, children of the
## scrolled list), and the tab of the part at the pane's top follows the scroll (the last one at the bottom). The tab
## clicked stays on while its own scroll runs, even when the page's end stops it short of the top.
func spy(scroll: ScrollContainer, tabs: Array, heads: Array) -> void:
	var held := [null]
	for i in tabs.size():
		tabs[i].pressed.connect(
			func():
				held[0] = tabs[i]
				tabs[i].button_pressed = true
				scroll.scroll_vertical = int(heads[i].position.y)
				held[0] = null
		)
	var bar := scroll.get_v_scroll_bar()
	bar.value_changed.connect(
		func(v: float):
			if held[0] != null:
				return
			var on := 0
			for i in heads.size():
				if heads[i].position.y <= v + 8:
					on = i
			if v >= bar.max_value - bar.page - 1 and v > 0:
				on = heads.size() - 1
			tabs[on].button_pressed = true
			if tabs.has(scroll.get_viewport().gui_get_focus_owner()):
				tabs[on].grab_focus()  # the focus box on the lit tab, not on another
	)


## A button for what the sim does not have yet (the campaign): greyed, "coming" as its tooltip, no focus.
func _soon(parent: Node, t: String, kind_name: String) -> Button:
	var b := Button.new()
	b.text = t
	b.theme_type_variation = kind_name
	b.disabled = true
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = s("coming")
	b.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN
	parent.add_child(b)
	# Its kind's plain box (the themes give the disabled state none, or a lit one), the text greyed.
	b.add_theme_stylebox_override("disabled", b.get_theme_stylebox("normal"))
	return b


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
		_textures[file] = Img.load_texture(ProjectSettings.globalize_path(PHOTOS.path_join(file)))
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
