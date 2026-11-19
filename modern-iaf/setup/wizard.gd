# Modern IAF's setup wizard (modern-iaf/docs/setup.md): builds the sim's data under assets/ through IafSetup's sim_start
# (crates/iaf-godot/src/setup.rs, iaf_setup::sim_run: the iaf-sim steps with their stamps). Pages: Welcome (language,
# what it builds, sizes, the requirements, the Attributions button) → Imagery → Install → Done; the Attributions open
# as a modal dialog over the page. English and Hebrew (strings_<lang>.json, Settings.language); in Hebrew every
# control is mirrored (layout_direction RTL). The look is wizard_theme.gd alone (Godot's default dark theme with
# Heebo). Opened by ./modern-iaf-setup and by ./start-modern-iaf without the sim's data.
extends "res://shared/util/setup_wizard.gd"

const WizardTheme := preload("res://setup/wizard_theme.gd")
const Img := preload("res://shared/util/img.gd")

const TITLE := "Modern IAF"
## The logo's height in the top bar (px at a UI scale of 1).
const LOGO_H := 52.0
const PAGES := ["welcome", "imagery", "install", "done"]
const DEM_GB := 0.627
## The Sentinel-2 / WorldCover tiles under the 8 m nodes (14 of the theatre's 21), downloaded once into
## assets/source/imagery/sentinel2; the other 7 are cut once into kept 20 m extracts (modern-iaf/docs/terrain.md §1.1).
const S2_GB := 8.28
## The free space the tiles' download leaves (iaf_tools::imagery_run::S2_KEEP_FREE): a tile past it is read online.
const KEEP_FREE_GB := 5.0
const THEATRE_S2_GB := 0.47
const THEATRE_SURVEY_GB := 3.57
## The rest: the compiled data (0.02) and the OpenStreetMap extracts the coastline and the inland water are cut from
## (0.45: Israel and Palestine, Lebanon, Syria, Jordan, Egypt; iaf_tools::sim_coast::water_extracts), downloaded once.
const OTHER_GB := 0.47
const TIME_S2_MIN := 17
const TIME_SURVEY_MIN := 102
var strings := {}
var survey := false
var sheets := 0
## The GB of the sim's Sentinel-2 tiles already in the cache (IafSetup.sim_s2_cached).
var s2_cached := 0.0
## The optional steps the player left out (unticked Include; remembered by IafSetup.sim_save_excluded).
var excluded: Array = []
## The optional steps' sizes by id (IafSetup.sim_optional: built, download, disk, sources, shared).
var optional := {}
## The remove-its-data question after unticking a built step, its "also the downloads" tick, the step it asks about.
var remove_dialog: ConfirmationDialog
var remove_text: Label
var remove_downloads: CheckBox
var remove_id := ""
## The last run's steps as IafSetup.poll gave them at its end.
var last_steps := []
var page_label: Label
## The Done page's second button (Start the game is next_button).
var close_button: Button
var lang_pick: OptionButton
var req_ok := false
var s2_check: CheckBox
var survey_check: CheckBox
## The whole run's time left, under the status line while it runs ("all steps", or the step count unmeasured).
var total_label: Label
## The Attributions, a modal dialog opened from Welcome (Esc or Close closes it).
var credits_dialog: AcceptDialog
var rows_box: VBoxContainer
var done_label: Label


func _ready() -> void:
	# The window: 1100×720 times the UI scale, centred (./modern-iaf-setup starts it at 1100×720).
	_start_wizard(PAGES, Vector2i(1100, 720))
	get_window().title = "%s — %s" % [TITLE, "Setup"]
	log_name = "modern-iaf-setup"
	sheets = IafSetup.survey_sheets(assets)
	s2_cached = IafSetup.sim_s2_cached(assets) / 1e9
	survey = sheets > 0
	excluded = Array(IafSetup.sim_excluded(assets))
	_load_optional()
	_build()
	show_page(0)


## The logo (modern-iaf/branding/, tools/iaf-2026/logo.py): the horizontal lockup for a dark background, the mark
## on the leading side of the name in language `lang` ("en": MODERN IAF, "he": הזרוע הארוכה), `h` px tall,
## mipmapped so it stays smooth at every window size, `name` its accessible name. The wizard's top bar and the front
## end's (front_end.gd _mark: its top bar, the pause menu, the Mission accomplished panel) show it.
static func logo(lang: String, h: float, name: String) -> TextureRect:
	var t := TextureRect.new()
	t.name = "Logo"
	t.texture = Img.load_texture(ProjectSettings.globalize_path("res://branding/bar_%s_dark.png" % lang), true)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	t.custom_minimum_size = Vector2(h * t.texture.get_width() / t.texture.get_height(), h)
	t.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.accessibility_name = name
	return t


## The current language's string `key` (English when the Hebrew table lacks it).
func s(key: String) -> String:
	return strings.get(key, key)


# --- layout ---


## Builds every page in the current language; called again when the language changes.
func _build() -> void:
	strings = Settings.strings("res://setup/strings")
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
	# The top bar: the logo in the wizard's language, "Setup", the language (first page).
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	v.add_child(top)
	top.add_child(logo(Settings.language, LOGO_H, s("name")))
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
	_add_pages(body, [_page_welcome, _page_imagery, _page_install, _page_done])
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
	log_button = _button(foot, s("show_log"), func(): _show_log(not log_view.visible))
	close_button = _button(foot, s("close"), func(): get_tree().quit())
	close_button.name = "Close"
	next_button = _button(foot, "", _on_next)
	next_button.name = "Next"
	credits_dialog = _credits_dialog()
	remove_dialog = _remove_dialog()
	add_child(remove_dialog)


## A label in one of the theme's text kinds (wizard_theme.gd: "", "Heading", "Muted", "Note", "Readout").
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
	# What this computer needs: GDAL, curl and the space.
	var req := _vbox(4)
	req.name = "Requirements"
	_label(req, s("needs"), "Muted")
	_card(row, req).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hint := s(by_os("hint_linux", "hint_mac", "hint_windows"))
	req_ok = true
	for t in [["gdal", "GDAL"], ["curl", "curl"]]:
		var here: bool = tools.get(t[0], false)
		req_ok = req_ok and here
		_text(req, "%s: %s" % [t[1], s("found") if here else s("missing")], "Note")
	if not req_ok:
		_text(req, hint, "Note")
	var free := free_gb(assets)
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


## Every source the sim is built from and every tool it is made with, with its licence lines: shared/credits.json
## "sim", then "made_with" (both games' credits, docs/credits.md "Modern IAF data" and "Modern IAF's tools"), each
## {name, use (the strings key of its use), lines}. The game manual's Attributions appendix lists the same records.
static func credits() -> Array:
	var all: Dictionary = Settings.load_json("res://shared/credits.json")
	return all.get("sim", []) + all.get("made_with", [])


## The Attributions dialog: every source and its licence lines, scrolling; mirrored in Hebrew.
func _credits_dialog() -> AcceptDialog:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var d := _attributions(scroll)
	d.ok_button_text = s("close")
	var v := _vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	for c in credits():
		var box := _vbox(2)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 12)
		box.add_child(head)
		var name := _label(head, c.name, "Heading")
		name.text_direction = Control.TEXT_DIRECTION_LTR
		_label(head, s(c.use), "Muted")
		for line in c.lines:
			# The licence lines stay as their licences word them: English, left to right.
			var l := _text(box, line, "Note")
			l.text_direction = Control.TEXT_DIRECTION_LTR
		_card(v, box)
	return d


func _page_install() -> Control:
	var v := _vbox(10)
	v.name = "Install"
	install_note = _text(v, "")
	total_label = _text(v, "", "Muted")
	total_label.name = "Total"
	total_label.visible = false
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
	return v


# --- flow ---


## Switches the wizard's language (the sim's Settings.language, saved) and builds the pages again.
func set_language(lang: String) -> void:
	if lang == Settings.language:
		return
	Settings.language = lang
	Settings.save()
	var was := page
	_build()
	# Every step's row, the left-out ones too (a run's steps hold only the included ones).
	if running or finished:
		_fill_rows(IafSetup.sim_plan(survey))
	if finished:
		_show_result()
	show_page(was)


func _on_page(id: String) -> void:
	title_label.text = s("page_" + id)
	page_label.text = "%d / %d" % [page + 1, PAGES.size()]
	lang_pick.get_parent().visible = page == 0
	if id == "imagery":
		_on_choice()
	if id == "install" and not running and not finished:
		_fill_rows(IafSetup.sim_plan(survey))
		_note("")
		_preview_sim()


func _update() -> void:
	super()
	var pg := at()
	close_button.visible = pg == "done"
	total_label.visible = running
	match pg:
		"welcome":
			next_button.disabled = not req_ok
		"install":
			next_button.text = s("next") if finished and failed == "" else s("install")
			next_button.disabled = running
			for id in rows:
				rows[id].redo.disabled = running or id in excluded
				rows[id].retry.disabled = running
				if rows[id].include:
					rows[id].include.disabled = running
		"done":
			next_button.text = s("start_game")
	next_button.theme_type_variation = "Primary" if pg == "done" else ""


func _finish() -> void:
	start_game()


## Opens the sim's front end in this process, as ./start-modern-iaf starts it: the project's own window (not the
## wizard's 1100×720 at the UI scale), the player's display mode, the devices read from the keys setup just built.
func start_game() -> void:
	var win := get_window()
	win.content_scale_factor = 1.0
	if DisplayServer.get_name() != "headless":
		win.mode = Window.MODE_FULLSCREEN if Settings.fullscreen else Window.MODE_MAXIMIZED
	Settings.apply_devices()
	get_tree().change_scene_to_file(Settings.front_end_scene())


## The whole run's time left from IafSetup.poll: "all steps" from the measured durations, else the step count.
## Never less than a running row's own time left (the rows estimate from this run's pace, poll from earlier runs');
## under a second (nothing measured left to run) it shows nothing rather than "about 0 s".
func total_text(p: Dictionary) -> String:
	if p.left < 0.0:
		return s("step_of") % [p.step, p.of]
	var left: float = p.left
	for id in rows:
		left = maxf(left, rows[id].get("left", -1.0))
	return s("all_left") % _duration(left) if left >= 1.0 else ""


## The step rows: the name, its own "Run again" tick (that step only, though it is up to date), the bar, the state;
## under a skipped or failed step its reason and Retry (runs setup again: the step has no stamp, so it runs).
func _fill_rows(steps: Array) -> void:
	for st in steps:
		var r: Dictionary = rows.get(st.id, {})
		if r.is_empty():
			var box := _vbox(2)
			box.name = "Row_" + st.id
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 12)
			box.add_child(h)
			var id: String = st.id
			# Include: an optional step can be left out (neither downloaded nor built). A required one (the plan's
			# `required`) has no tick: an empty slot as wide as one keeps the names in line.
			var include := CheckBox.new()
			include.name = "Include"
			h.add_child(include)
			rows_box.add_child(box)
			if st.get("required", false):
				var slot := Control.new()
				slot.name = "Required"
				slot.custom_minimum_size = include.get_combined_minimum_size()
				h.remove_child(include)
				include.free()
				include = null
				h.add_child(slot)
			else:
				include.tooltip_text = s("include")
				include.button_pressed = not id in excluded
				include.toggled.connect(func(on): _on_include(id, on))
			var names := _vbox(0)
			names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(names)
			var title := Label.new()
			title.text = s("step_" + st.id)
			title.tooltip_text = st.title
			names.add_child(title)
			var sizes := _label(names, "", "Note")
			sizes.name = "Sizes"
			var redo := CheckBox.new()
			redo.name = "RunAgain"
			redo.text = s("row_redo")
			redo.toggled.connect(func(_on): _forget_run())
			h.add_child(redo)
			var bar := ProgressBar.new()
			bar.custom_minimum_size = Vector2(220, 10)
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			bar.max_value = 1.0
			bar.show_percentage = false
			h.add_child(bar)
			# A fixed column as wide as the longest state ("running · this step: about 2 h 00 min left"): the time left
			# never pushes the name, sizes and bar aside; a longer text wraps to a second line.
			var state := Label.new()
			state.custom_minimum_size.x = 300
			state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			h.add_child(state)
			var why_row := HBoxContainer.new()
			why_row.add_theme_constant_override("separation", 12)
			box.add_child(why_row)
			var why := _text(why_row, "", "Note")
			why.name = "Reason"
			var retry := _button(why_row, s("retry"), func(): retry_step(id))
			retry.name = "Retry"
			why_row.visible = false
			r = {
				"bar": bar,
				"state": state,
				"redo": redo,
				"why": why_row,
				"reason": why,
				"retry": retry,
				"include": include,
				"sizes": sizes,
				"required": st.get("required", false),
			}
			rows[st.id] = r
			_show_sizes(id)
		var name: String = st.get("state", "waiting")
		if st.id in excluded:
			name = "excluded"
		r.state.text = s("state_" + name)
		r.why.visible = name in ["skipped", "failed"] and not running
		var detail: String = st.get("detail", "")
		r.reason.text = reason(detail)
		# iaf-setup's own wording is English: left to right; ours follows the page.
		var raw: bool = r.reason.text == detail
		r.reason.text_direction = Control.TEXT_DIRECTION_LTR if raw else Control.TEXT_DIRECTION_INHERITED
		var f: float = st.get("fraction", 0.0)
		r.left = -1.0
		if name == "running":
			r.left = time_left(r, f)
			if r.left >= 0.0:
				r.state.text = s("left") % [r.state.text, _duration(r.left)]
		r.state.tooltip_text = st.get("detail", "")
		r.bar.value = f
		r.bar.modulate.a = 1.0 if name in ["running", "done", "up_to_date"] else 0.35


## Which steps are up to date already, checked in the background; the rows show it until Install.
func _preview_sim() -> void:
	_preview(
		"sim_preview",
		[assets, repo, "1" if survey else "0"] + excluded,
		func(up: Dictionary):
			for id in rows:
				var u: bool = up.get(id, false)
				rows[id].state.text = s("state_up_to_date") if u else s("state_will_run")
				if id in excluded:
					rows[id].state.text = s("state_excluded")
	)


## The optional steps' sizes, read again (after a run or a removal).
func _load_optional() -> void:
	optional.clear()
	for o in IafSetup.sim_optional(assets):
		optional[o.id] = o


## An optional row's sizes line: what it downloads (none when assets/source holds it) and what it takes on disk; the
## terrain's row: "Nothing to download" when its run would read only local files.
func _show_sizes(id: String) -> void:
	var r: Dictionary = rows[id]
	var o: Dictionary = optional.get(id, {})
	if id == "sim-terrain":
		# A built theatre rebuilt for a code change reads only the caches: said on its row (the user, 2026-11-13).
		r.sizes.visible = IafSetup.sim_terrain_fetch(assets, survey).is_empty()
		r.sizes.text = s("dl_none")
		return
	r.sizes.visible = not o.is_empty()
	if o.is_empty():
		return
	var dl: String = s("dl_none") if o.download == 0 else s("dl") % _gb(o.download / 1e9)
	r.sizes.text = "%s · %s" % [dl, (s("disk_built") if o.built else s("disk_will")) % _gb(o.disk / 1e9)]


## The step's failure or skip reason in the UI language where the text is ours, else as iaf-setup wrote it.
func reason(detail: String) -> String:
	if detail.begins_with("GDAL is needed"):
		return s("why_gdal")
	if "cannot be reached (offline?)" in detail:
		return s("why_offline")
	if detail.begins_with("built, incomplete: "):
		return s("why_incomplete") % detail.get_slice(" ", 2).to_int()
	return detail


## Include ticked or unticked: remembered at once; unticking a built step asks whether to remove its data.
func _on_include(id: String, on: bool) -> void:
	if on:
		excluded.erase(id)
	elif not id in excluded:
		excluded.append(id)
	IafSetup.sim_save_excluded(assets, PackedStringArray(excluded))
	_forget_run()
	rows[id].state.text = s("state_will_run") if on else s("state_excluded")
	_update()
	if not on and optional.get(id, {}).get("built", false):
		ask_remove(id)


## The remove-its-data question for the built step `id`: the space it frees; the downloads only when ticked, never
## when another setup in this folder shares them.
func ask_remove(id: String) -> void:
	var o: Dictionary = optional[id]
	var locked: bool = o.shared and id == "sim-textures"
	remove_id = id
	remove_text.text = s("remove_q") % [s("step_" + id), _gb(o.disk / 1e9)]
	if locked:
		remove_text.text = s("remove_kept") % s("step_" + id)
	remove_downloads.button_pressed = false
	remove_downloads.disabled = o.shared or o.sources == 0
	remove_downloads.text = s("remove_shared") if o.shared else s("remove_downloads") % _gb(o.sources / 1e9)
	remove_dialog.get_ok_button().disabled = locked
	remove_dialog.popup_centered(Vector2i(660, 0))


func _remove_dialog() -> ConfirmationDialog:
	var d := ConfirmationDialog.new()
	d.name = "Remove"
	d.title = s("remove_title")
	d.ok_button_text = s("remove")
	d.cancel_button_text = s("keep")
	d.exclusive = true
	d.set_layout_direction(Window.LAYOUT_DIRECTION_RTL if Settings.language == "he" else Window.LAYOUT_DIRECTION_LTR)
	var v := _vbox(10)
	d.add_child(v)
	remove_text = _text(v, "")
	remove_text.custom_minimum_size.x = 620
	remove_downloads = CheckBox.new()
	remove_downloads.name = "AlsoDownloads"
	v.add_child(remove_downloads)
	d.confirmed.connect(func(): remove_data(remove_id, remove_downloads.button_pressed))
	return d


## Removes a left-out step's data (and its downloads when asked); the status line says what it freed.
func remove_data(id: String, downloads: bool) -> void:
	var res: Dictionary = IafSetup.sim_remove(assets, id, downloads)
	var ok: bool = res.error == ""
	_note(s("removed") % [s("step_" + id), _gb(res.freed / 1e9)] if ok else s("not_removed") % res.error)
	_load_optional()
	_show_sizes(id)


## A ticked "Run again" makes a finished run installable again (the Install button comes back).
func _forget_run() -> void:
	if finished and not running:
		finished = false
		failed = ""
		_note("")
		_update()


## Retry under a skipped or failed step: that step (and what is not up to date) runs again.
func retry_step(id: String) -> void:
	rows[id].redo.set_pressed_no_signal(true)
	start_install()


func _run(redo: PackedStringArray) -> String:
	return setup.sim_start(assets, repo, survey, redo, PackedStringArray(excluded), log_file)


func _polled(p: Dictionary) -> void:
	_fill_rows(p.steps)
	total_label.text = total_text(p)


func _finished(p: Dictionary) -> void:
	last_steps = p.steps
	_load_optional()
	for id in optional:
		if rows.has(id):
			_show_sizes(id)
	_show_result()


## The finished run on the Install and Done pages (again after the pages are built anew in another language).
func _show_result() -> void:
	_fill_rows(last_steps)
	var up: int = last_steps.filter(func(st): return st.state == "up_to_date").size()
	var skipped: int = last_steps.filter(func(st): return st.state == "skipped").size()
	var done := (
		s("finished") % [last_steps.size() - up - skipped, up]
		if skipped == 0
		else s("finished_skipped") % [last_steps.size() - up - skipped, up, skipped]
	)
	_note((s("stopped") % [failed, log_file]) if failed != "" else done)
	for id in rows:
		rows[id].redo.set_pressed_no_signal(false)
	done_label.text = s("set_up") if failed == "" else s("not_set_up") % failed
	if failed != "":
		_show_log(true)


## "1.1 GB" / "620 MB": one left-to-right piece (a Unicode isolate, a no-break space), so a Hebrew line keeps the number
## before its unit and on one line.
static func _gb(x: float) -> String:
	var t := ("%.0f\u00a0MB" % (x * 1000)) if x < 1.0 else ("%.1f\u00a0GB" % x)
	return "\u2066" + t + "\u2069"


## A duration in the wizard's language.
func _duration(sec: float) -> String:
	return duration(sec, Settings.language == "he")
