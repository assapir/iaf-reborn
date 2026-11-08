# Modern IAF's setup wizard (iaf-2026/docs/setup.md): builds the sim's data under assets/ through IafSetup's sim_start
# (crates/iaf-godot/src/setup.rs, iaf_setup::sim_run: the iaf-sim steps with their stamps). Pages: Welcome (language,
# what it builds, sizes, the requirements, the Attributions button) → Imagery → Install → Done; the Attributions open
# as a modal dialog over the page. English and Hebrew (strings_<lang>.json, Settings.language); in Hebrew every
# control is mirrored (layout_direction RTL). The look is wizard_theme.gd alone (Godot's default dark theme with
# Heebo). Opened by ./modern-iaf-setup and by ./modern-iaf without the sim's data.
extends Control

const WizardTheme := preload("res://setup/wizard_theme.gd")
const WizardUtil := preload("res://shared/util/wizard_util.gd")

const TITLE := "Modern IAF"
const PAGES := ["welcome", "imagery", "install", "done"]
const DEM_GB := 0.627
## The Sentinel-2 / WorldCover tiles over the theatre, downloaded once into assets/source/imagery/sentinel2.
const S2_GB := 11.4
## The free space the tiles' download leaves (iaf_tools::imagery_run::S2_KEEP_FREE): a tile past it is read online.
const KEEP_FREE_GB := 5.0
const THEATRE_S2_GB := 0.47
const THEATRE_SURVEY_GB := 3.57
## The rest: the compiled data (0.02) and the OpenStreetMap extracts the coastline and the inland water are cut from
## (0.45: Israel and Palestine, Lebanon, Syria, Jordan, Egypt; iaf_tools::sim_coast::water_extracts), downloaded once.
const OTHER_GB := 0.47
const TIME_S2_MIN := 17
const TIME_SURVEY_MIN := 102
## Every source the sim is built from, with its licence line as the licence asks for it (the Copernicus lines
## verbatim, terrain.md §5; sound.md §6; docs/credits.md "Modern IAF data"): [name, strings key of its use, lines].
const CREDITS := [
	[
		"Copernicus DEM GLO-30",
		"for_dem",
		[
			(
				"produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH "
				+ "2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved"
			),
			(
				"The organisations in charge of the Copernicus programme by law or by delegation do not incur any "
				+ "liability for any use of the Copernicus WorldDEM-30"
			),
		]
	],
	[
		"ESA WorldCover Sentinel-2",
		"for_s2",
		[
			(
				"Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium; ESA "
				+ "WorldCover project 2021 (CC BY 4.0)"
			)
		]
	],
	["Survey of Israel", "for_survey", ["© Survey of Israel 2015, via data.gov.il"]],
	[
		"OpenStreetMap",
		"for_osm",
		[
			(
				"Airbase, runway, coastline, inland water, building and road data © OpenStreetMap contributors, available under "
				+ "the Open Database Licence (ODbL) 1.0: openstreetmap.org/copyright; Geofabrik extracts (Israel and "
				+ "Palestine, Lebanon, Syria, Jordan, Egypt)"
			)
		]
	],
	["OurAirports", "for_ourairports", ["OurAirports data (public domain), ourairports.com"]],
	[
		"Microsoft Global ML Building Footprints",
		"for_scenery",
		[
			"Microsoft Global ML Building Footprints (CDLA-Permissive-2.0), github.com/microsoft/GlobalMLBuildingFootprints"
		]
	],
	["GHS-BUILT-H R2023A", "for_scenery", ["GHS-BUILT-H R2023A, European Commission, Joint Research Centre (JRC)"]],
	[
		"Global Canopy Height 2020",
		"for_trees",
		["Global Canopy Height 2020, Lang, Jetz, Schindler, Wegner; ETH Zürich EcoVision Lab (CC BY 4.0)"]
	],
	[
		"freesound.org",
		"for_sounds",
		[
			(
				"CC0 1.0. Authors: ikbenraar, TiesWijnen, pillwave, 77Pacer, nuckan, qubodup, Seidhepriest, Jetrod, "
				+ "craigsmith (the USC Gold / Red / Sunset Editorial libraries), LilMati, Rudmer_Rotteveel, pushkin, "
				+ "xkeril, elliott.klein, DeqstersLab, RutgerMuller, SoundDesignForYou, tranzfusion"
			)
		]
	],
	[
		"Piper",
		"for_voices",
		[
			(
				"Piper text to speech (MIT); the voices kristin, john and norman, trained on LibriVox recordings "
				+ "(public domain)"
			)
		]
	],
	[
		"FlightGear F-16",
		"for_f16",
		[
			(
				"The FlightGear F-16 (github.com/NikolaiVChr/f16) by Erik Hofman, Nikolai V. Chr., J Maverick 16, "
				+ 'Martin "Pegasus" Schmitt, Prohm "Rama" Snitwong and the other authors in its authors.txt, '
				+ "GPL 2.0 or later"
			)
		]
	],
	["F-35I", "for_f35", ['"Lockheed Martin F35 Lightning II" by andertan (sketchfab.com), CC BY 4.0']],
	[
		"NASA TP-1538",
		"for_fm",
		[
			(
				"L. T. Nguyen et al., NASA TP-1538 (1979), a work of the U.S. Government (public domain); the "
				+ "jets' published figures, each cited in the data files"
			)
		]
	],
	[
		"Heebo",
		"for_font",
		["Copyright 2014 The Heebo Project Authors (github.com/OdedEzer/heebo), SIL Open Font License 1.1"]
	],
	[
		"Hershey Fonts",
		"for_hud_font",
		[
			(
				"The Hershey Fonts were originally created by Dr. A. V. Hershey while working at the U. S. National "
				+ "Bureau of Standards"
			),
			"The format of the Font data in this distribution was originally created by James Hurt, Cognition, Inc.",
		]
	],
	[
		"Wikimedia Commons",
		"for_photos",
		[
			"F-16I Sufa 407 and F-35I Adir in flight: Major Ofer, Israeli Air Force, CC BY 4.0",
			"F-16I Sufa 851 at Tel Nof: MathKnight and Zachi Evenor, CC BY 4.0",
			"F-16D Barak 034: Zachi Evenor and MathKnight, CC BY 2.0",
		]
	],
]
var setup := IafSetup.new()
var assets := ""
var repo := ""
var tools := {}
var strings := {}
var page := 0
var survey := false
var sheets := 0
## The GB of the sim's Sentinel-2 tiles already in the cache (IafSetup.sim_s2_cached).
var s2_cached := 0.0
var running := false
var finished := false
var failed := ""
var log_file := ""
## The last run's steps as IafSetup.poll gave them at its end.
var last_steps := []
## The background preview (which steps are up to date), by job name.
var jobs := {}
var previews := 0

var title_label: Label
var page_label: Label
var back_button: Button
var next_button: Button
var log_button: Button
var pages: Array[Control] = []
var lang_pick: OptionButton
var req_ok := false
var s2_check: CheckBox
var survey_check: CheckBox
var install_note: Label
## The Attributions, a modal dialog opened from Welcome (Esc or Close closes it).
var credits_dialog: AcceptDialog
var redo_check: CheckBox
var rows_box: VBoxContainer
var rows := {}
var log_view: TextEdit
var done_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_window().title = "%s — %s" % [TITLE, "Setup"]
	# The window: 1100×720 times the UI scale, centred (./modern-iaf-setup starts it at 1100×720).
	(func(): WizardUtil.resize_window(self, Vector2i(1100, 720))).call_deferred()
	assets = Settings.assets_dir()
	repo = ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	tools = IafSetup.tools()
	sheets = IafSetup.survey_sheets(assets)
	s2_cached = IafSetup.sim_s2_cached(assets) / 1e9
	survey = sheets > 0
	_build()
	show_page(0)


func _exit_tree() -> void:
	if running:
		setup.cancel()


## The current language's string `key` (English when the Hebrew table lacks it).
func s(key: String) -> String:
	return strings.get(key, key)


func _load_strings() -> void:
	var f := "res://setup/strings_%s.json" % ("he" if Settings.language == "he" else "en")
	strings = JSON.parse_string(FileAccess.get_file_as_string(f))


# --- layout ---


## Builds every page in the current language; called again when the language changes.
func _build() -> void:
	_load_strings()
	for c in get_children():
		remove_child(c)
		c.queue_free()
	pages.clear()
	rows.clear()
	layout_direction = Control.LAYOUT_DIRECTION_RTL if Settings.language == "he" else Control.LAYOUT_DIRECTION_LTR
	theme = WizardTheme.make()
	# The theme's own background (a Panel fills the window).
	var bg := Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	margin.add_child(v)
	# The top bar: the name, "Setup", the language (first page).
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	v.add_child(top)
	_label(top, s("name"), "Title")
	_label(top, s("setup"), "Muted")
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(gap)
	# The language, on the first page (the sim's Settings.language).
	var lang := HBoxContainer.new()
	lang.name = "LanguageRow"
	lang.add_theme_constant_override("separation", 10)
	top.add_child(lang)
	_label(lang, s("language"), "Muted")
	lang_pick = OptionButton.new()
	lang_pick.name = "Language"
	lang_pick.add_item("English")
	lang_pick.add_item("עברית")
	lang_pick.selected = 1 if Settings.language == "he" else 0
	lang_pick.item_selected.connect(func(i): set_language("he" if i == 1 else "en"))
	lang.add_child(lang_pick)
	v.add_child(HSeparator.new())
	title_label = _label(v, "", "Heading")
	var body := MarginContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	for f in [_page_welcome, _page_imagery, _page_install, _page_done]:
		var p: Control = f.call()
		# Every page scrolls in the body, so the footer stays in the window; Install scrolls its own step list.
		if p.name != "Install":
			var scroll := ScrollContainer.new()
			scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			scroll.add_child(p)
			p = scroll
		p.visible = false
		body.add_child(p)
		pages.append(p)
	v.add_child(HSeparator.new())
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	v.add_child(foot)
	back_button = _button(foot, "", _on_back)
	page_label = _label(foot, "", "Muted")
	page_label.text_direction = Control.TEXT_DIRECTION_LTR
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(fill)
	log_button = _button(
		foot,
		s("show_log"),
		func():
			log_view.visible = not log_view.visible
			log_button.text = s("hide_log") if log_view.visible else s("show_log")
	)
	next_button = _button(foot, "", _on_next)
	credits_dialog = _credits_dialog()
	add_child(credits_dialog)


## A label in one of the theme's text kinds (wizard_theme.gd: "", "Title", "Heading", "Muted", "Note", "Readout",
## "Code").
func _label(parent: Control, t: String, kind := "") -> Label:
	var l := Label.new()
	l.text = t
	l.theme_type_variation = kind
	if parent != null:
		parent.add_child(l)
	return l


## A wrapping text line.
func _text(parent: Control, t: String, kind := "") -> Label:
	var l := _label(parent, t, kind)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## A command or path: always left to right, also on a Hebrew page.
func _code(parent: Control, t: String) -> Label:
	var l := _text(parent, t, "Code")
	l.text_direction = Control.TEXT_DIRECTION_LTR
	return l


func _button(parent: Control, t: String, on: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size.x = 130
	b.pressed.connect(on)
	parent.add_child(b)
	return b


## A card (the theme's "Card" panel) holding `inner`.
func _card(parent: Control, inner: Control) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = "Card"
	p.add_child(inner)
	parent.add_child(p)
	return p


func _vbox(sep := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


# --- pages ---


func _page_welcome() -> Control:
	var v := _vbox(8)
	_label(v, s("builds"), "Muted")
	for k in ["item_terrain", "item_bases", "item_models", "item_sounds", "item_missions"]:
		_card(v, _label(null, s(k)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	var dl := _gb(DEM_GB + S2_GB)
	var kept := DEM_GB + S2_GB + OTHER_GB
	var disk := "%s – %s" % [_gb(kept + THEATRE_S2_GB), _gb(kept + THEATRE_SURVEY_GB)]
	var time := "%s – %s" % [_duration(TIME_S2_MIN * 60), _duration(TIME_SURVEY_MIN * 60)]
	var dl_note := s("download_note") % [_gb(DEM_GB), _gb(S2_GB)]
	for box in [[s("download"), dl, dl_note], [s("disk"), disk, s("disk_note")], [s("time"), time, s("time_note")]]:
		var c := _vbox(4)
		_label(c, box[0], "Muted")
		_label(c, box[1], "Readout")
		_text(c, box[2], "Note")
		_card(row, c).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# What this computer needs: GDAL, curl, Python 3 and the space.
	var req := _vbox(4)
	req.name = "Requirements"
	_label(req, s("needs"), "Muted")
	_card(row, req).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hint := s({"macOS": "hint_mac", "Windows": "hint_windows"}.get(OS.get_name(), "hint_linux"))
	req_ok = true
	for t in [["gdal", "GDAL"], ["curl", "curl"], ["python3", "Python 3"]]:
		var here: bool = tools.get(t[0], false)
		req_ok = req_ok and here
		_text(req, "%s: %s" % [t[1], s("found") if here else s("missing")], "Note")
	if not req_ok:
		_text(req, hint, "Note")
	var free := WizardUtil.free_gb(assets)
	# The space the imagery choice needs (the Survey is chosen at the start when its sheets are there), and the
	# Sentinel-2 tiles still to download; tiles with no room are read online (docs/imagery.md §2).
	var need := DEM_GB + (THEATRE_SURVEY_GB if survey else THEATRE_S2_GB) + OTHER_GB
	var tiles := maxf(S2_GB - s2_cached, 0.0)
	var credits_row := HBoxContainer.new()
	credits_row.add_theme_constant_override("separation", 14)
	v.add_child(credits_row)
	_button(credits_row, s("credits"), func(): credits_dialog.popup_centered(Vector2i(900, 560))).name = "Credits"
	if free >= 0:
		var t := (s("free") % _gb(free)) if free >= need else (s("free_low") % [_gb(free), _gb(need + tiles)])
		_text(req, t, "Note")
		req_ok = req_ok and free >= need
		if free >= need and tiles > 0 and free < need + tiles + KEEP_FREE_GB:
			var online := _text(
				credits_row, s("free_online") % _gb(minf(need + tiles + KEEP_FREE_GB - free, tiles)), "Note"
			)
			online.name = "Online"
	return v


func _page_imagery() -> Control:
	var v := _vbox(8)
	var group := ButtonGroup.new()
	s2_check = _choice(v, group, s("s2"), s("s2_note") % [_gb(THEATRE_S2_GB), _duration(TIME_S2_MIN * 60)], true)
	var note := (
		(s("survey_note") % [sheets, _gb(THEATRE_SURVEY_GB), _duration(TIME_SURVEY_MIN * 60)])
		if sheets > 0
		else s("survey_needs") % "assets/source/imagery/mapi2015"
	)
	survey_check = _choice(v, group, s("survey"), note, sheets > 0)
	survey_check.button_pressed = survey
	s2_check.button_pressed = not survey
	for c in [s2_check, survey_check]:
		c.toggled.connect(func(_on): _on_choice())
	return v


## An imagery choice: a radio button in a card with its note.
func _choice(parent: Control, group: ButtonGroup, label: String, note: String, available: bool) -> CheckBox:
	var v := _vbox(2)
	var c := CheckBox.new()
	c.text = label
	c.button_group = group
	c.disabled = not available
	c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(c)
	_text(v, note, "Note")
	_card(parent, v)
	return c


func _on_choice() -> void:
	survey = survey_check.button_pressed and not survey_check.disabled


## The Attributions dialog: every source and its licence lines, scrolling; mirrored in Hebrew.
func _credits_dialog() -> AcceptDialog:
	var d := AcceptDialog.new()
	d.name = "Attributions"
	d.title = s("credits")
	d.ok_button_text = s("close")
	d.exclusive = true
	d.set_layout_direction(Window.LAYOUT_DIRECTION_RTL if Settings.language == "he" else Window.LAYOUT_DIRECTION_LTR)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	d.add_child(scroll)
	var v := _vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	for c in CREDITS:
		var box := _vbox(2)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 12)
		box.add_child(head)
		var name := _label(head, c[0], "Heading")
		name.text_direction = Control.TEXT_DIRECTION_LTR
		_label(head, s(c[1]), "Muted")
		for line in c[2]:
			# The licence lines stay as their licences word them: English, left to right.
			var l := _text(box, line, "Note")
			l.text_direction = Control.TEXT_DIRECTION_LTR
		_card(v, box)
	return d


func _page_install() -> Control:
	var v := _vbox(10)
	v.name = "Install"
	install_note = _text(v, "")
	redo_check = CheckBox.new()
	redo_check.text = s("redo")
	v.add_child(redo_check)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	rows_box = _vbox(6)
	rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows_box)
	log_view = TextEdit.new()
	log_view.editable = false
	log_view.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	log_view.custom_minimum_size.y = 200
	log_view.text_direction = Control.TEXT_DIRECTION_LTR
	log_view.visible = false
	v.add_child(log_view)
	return v


func _page_done() -> Control:
	var v := _vbox(8)
	done_label = _text(v, "", "Heading")
	var win := OS.get_name() == "Windows"
	_text(v, s("how_start"), "Muted")
	_code(v, ".\\modern-iaf.ps1" if win else "./modern-iaf")
	return v


# --- flow ---


## Switches the wizard's language (the sim's Settings.language, saved) and builds the pages again.
func set_language(lang: String) -> void:
	if lang == Settings.language:
		return
	Settings.language = lang
	Settings.save()
	var at := page
	_build()
	if finished:
		_show_result()
	show_page(at)


func show_page(n: int) -> void:
	page = clampi(n, 0, PAGES.size() - 1)
	for i in pages.size():
		pages[i].visible = i == page
	title_label.text = s("page_" + PAGES[page])
	page_label.text = "%d / %d" % [page + 1, PAGES.size()]
	lang_pick.get_parent().visible = page == 0
	if PAGES[page] == "imagery":
		_on_choice()
	if PAGES[page] == "install" and not running and not finished:
		_fill_rows(IafSetup.sim_plan(survey))
		_note("")
		_preview()
	_update()


func _update() -> void:
	var pg: String = PAGES[page]
	back_button.visible = page > 0 and pg != "done"
	back_button.text = s("cancel") if running else s("back")
	log_button.visible = pg == "install"
	next_button.disabled = false
	next_button.text = s("next")
	match pg:
		"welcome":
			next_button.disabled = not req_ok
		"install":
			next_button.text = s("next") if finished and failed == "" else s("install")
			next_button.disabled = running
			redo_check.disabled = running
		"done":
			next_button.text = s("done")


func _on_back() -> void:
	if running:
		setup.cancel()
		_note(s("cancelling"))
		return
	# Leaving Install forgets the last run: changed choices can be installed.
	if PAGES[page] == "install":
		finished = false
		failed = ""
	show_page(page - 1)


func _on_next() -> void:
	match PAGES[page]:
		"install":
			if finished and failed == "":
				show_page(page + 1)
			else:
				start_install()
		"done":
			get_tree().quit()
		_:
			show_page(page + 1)


## The Install page's status line, hidden while it is empty.
func _note(t: String) -> void:
	install_note.text = t
	install_note.visible = t != ""


func _fill_rows(steps: Array) -> void:
	for st in steps:
		var r: Dictionary = rows.get(st.id, {})
		if r.is_empty():
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 12)
			var title := Label.new()
			title.text = s("step_" + st.id)
			title.tooltip_text = st.title
			title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(title)
			var bar := ProgressBar.new()
			bar.custom_minimum_size = Vector2(220, 10)
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			bar.max_value = 1.0
			bar.show_percentage = false
			h.add_child(bar)
			var state := Label.new()
			state.custom_minimum_size.x = 220
			h.add_child(state)
			rows_box.add_child(h)
			r = {"bar": bar, "state": state}
			rows[st.id] = r
		var name: String = st.get("state", "waiting")
		r.state.text = s("state_" + name)
		var f: float = st.get("fraction", 0.0)
		if name == "running":
			r.started = r.get("started", Time.get_ticks_msec())
			var t: float = (Time.get_ticks_msec() - int(r.started)) / 1000.0
			if t > 30.0 and f > 0.02:
				r.state.text = s("left") % [r.state.text, _duration(t * (1.0 - f) / f)]
		r.state.tooltip_text = st.get("detail", "")
		r.bar.value = f
		r.bar.modulate.a = 1.0 if name in ["running", "done", "up_to_date"] else 0.35


## Which steps are up to date already, checked in the background; the rows show it until Install.
func _preview() -> void:
	for id in rows:
		rows[id].state.text = s("state_checking")
	# An older check still running (other choices) answers to nobody: its result is fetched and dropped, so IafSetup
	# forgets it.
	for j in jobs:
		jobs[j] = func(_r): pass
	previews += 1
	var job := "sim_preview#%d" % previews
	jobs[job] = func(up: Dictionary):
		if running or finished:
			return
		for id in rows:
			var u: bool = up.get(id, false)
			rows[id].state.text = s("state_up_to_date") if u else s("state_will_run")
	setup.begin(job, PackedStringArray([assets, repo, "1" if survey else "0"]))


func start_install() -> void:
	log_view.text = ""
	failed = ""
	finished = false
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("T", "-")
	log_file = assets.path_join("logs/modern-iaf-setup-%s.log" % stamp)
	var redo := PackedStringArray(["*"] if redo_check.button_pressed else [])
	var err: String = setup.sim_start(assets, repo, survey, redo, log_file)
	if err != "":
		_note(s("not_started") % err)
		return
	running = true
	log_view.text = "%s\n" % log_file
	_note(s("installing"))
	_update()


func _process(_delta: float) -> void:
	for job in jobs.keys():
		var r: String = setup.result(job)
		if r != "":
			var done: Callable = jobs[job]
			jobs.erase(job)
			done.call(JSON.parse_string(r))
	if not running:
		return
	var p: Dictionary = setup.poll()
	_fill_rows(p.steps)
	if p.log.size() > 0:
		log_view.text += "\n".join(p.log) + "\n"
		log_view.scroll_vertical = log_view.get_line_count()
	if p.done:
		running = false
		finished = true
		failed = p.error
		last_steps = p.steps
		_show_result()
	_update()


## The finished run on the Install and Done pages (again after the pages are built anew in another language).
func _show_result() -> void:
	_fill_rows(last_steps)
	var up: int = last_steps.filter(func(st): return st.state == "up_to_date").size()
	_note((s("stopped") % [failed, log_file]) if failed != "" else s("finished") % [last_steps.size() - up, up])
	done_label.text = s("set_up") if failed == "" else s("not_set_up") % failed
	if failed != "":
		log_view.visible = true
		log_button.text = s("hide_log")


## "1.1 GB" / "620 MB": one left-to-right piece (a Unicode isolate, a no-break space), so a Hebrew line keeps the number
## before its unit and on one line.
static func _gb(x: float) -> String:
	var t := ("%.0f\u00a0MB" % (x * 1000)) if x < 1.0 else ("%.1f\u00a0GB" % x)
	return "\u2066" + t + "\u2069"


## A duration in the wizard's language.
func _duration(sec: float) -> String:
	return WizardUtil.duration(sec, Settings.language == "he")
