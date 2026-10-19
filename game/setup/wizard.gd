# The setup wizard (docs/setup.md): from the player's own CDs to the game data under assets/, through IafSetup
# (crates/iaf-godot/src/setup.rs, the iaf-setup pipeline in-process). Pages: Requirements → Welcome → Your CD →
# Optional → Extras → Summary → Install → Done. Running it again adds or redoes things: the last inputs
# (assets/setup.json) fill the pages, and the steps whose inputs did not change are "up to date".
# Opened by ./setup, by ./iafjets without game data, and by startup.gd when assets/converted is missing.
extends Control

const TITLE := "Jane's IAF (reborn) — Setup"
const PAGES := ["Requirements", "Welcome", "Your CD", "Optional", "Extras", "Summary", "Install", "Done"]
## The game data without imagery: the install, the conversions (GB).
const BASE_GB := 3.0
const STATE_TEXT := {
	"waiting": "waiting", "running": "running", "up_to_date": "up to date", "done": "done", "skipped": "skipped",
	"failed": "FAILED", "blocked": "not run", "cancelled": "cancelled",
}

## Tests: only these steps (and what they wait for) run.
var only_steps := PackedStringArray()

var setup := IafSetup.new()
var assets := ""
var repo := ""
var tools := {}
var page := 0
var running := false
var finished := false
var failed := ""

var title_label: Label
var margin: MarginContainer
var body: Control
var back_button: Button
var next_button: Button
var pages: Array[Control] = []

# Requirements
var req_box: VBoxContainer
var req_ok := false
# Your CD
var cd_row: Dictionary
var cd_ok := false
# Optional
var patch_row: Dictionary
var hebrew_row: Dictionary
var brief_row: Dictionary
var menu_row: Dictionary
var packs_box: VBoxContainer
# Extras
var mapi_check: CheckBox
var mapi_scope: OptionButton
var sentinel_check: CheckBox
var refresh_check: CheckBox
var refresh_note: Label
var guides_check: CheckBox
var stale_thread: Thread
# Summary / Install
var summary_label: RichTextLabel
var redo_check: CheckBox
var rows_box: VBoxContainer
var rows := {}
var install_note: Label
var log_view: TextEdit
var log_button: Button
var done_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_window().title = TITLE
	_resize_window.call_deferred()
	assets = Settings.assets_dir()
	repo = ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	tools = IafSetup.tools()
	_build()
	_prefill()
	get_window().files_dropped.connect(_on_files_dropped)
	show_page(0)


func _exit_tree() -> void:
	if running:
		setup.cancel()
	if stale_thread != null and stale_thread.is_started():
		stale_thread.wait_to_finish()


# --- layout ---

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.14, 0.16)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	resized.connect(_cap_width)
	theme = _theme()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	margin.add_child(v)
	var header := Label.new()
	header.text = TITLE
	header.add_theme_font_size_override("font_size", 20)
	v.add_child(header)
	var steps := Label.new()
	steps.name = "Steps"
	steps.modulate = Color(1, 1, 1, 0.6)
	v.add_child(steps)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 30)
	v.add_child(title_label)
	v.add_child(HSeparator.new())
	body = MarginContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	v.add_child(HSeparator.new())
	var foot := HBoxContainer.new()
	v.add_child(foot)
	back_button = Button.new()
	back_button.text = "Back"
	back_button.custom_minimum_size.x = 120
	back_button.pressed.connect(_on_back)
	foot.add_child(back_button)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(gap)
	next_button = Button.new()
	next_button.custom_minimum_size.x = 160
	next_button.pressed.connect(_on_next)
	foot.add_child(next_button)
	for f in [_page_requirements, _page_welcome, _page_cd, _page_optional, _page_extras, _page_summary,
			_page_install, _page_done]:
		var p: Control = f.call()
		p.visible = false
		body.add_child(p)
		pages.append(p)


func _vbox() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	return v


func _text(parent: Control, t: String, dim := false) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 400
	if dim:
		l.modulate = Color(1, 1, 1, 0.65)
	parent.add_child(l)
	return l


## A file picker row: label, path field, Browse, Clear and a status line; `check(path) -> [ok, text]`.
func _file_row(parent: Control, label: String, filters: PackedStringArray, check: Callable) -> Dictionary:
	var box := _vbox()
	box.add_theme_constant_override("separation", 4)
	parent.add_child(box)
	var l := Label.new()
	l.text = label
	box.add_child(l)
	var h := HBoxContainer.new()
	box.add_child(h)
	var edit := LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.placeholder_text = "drop the file here, or Browse…"
	h.add_child(edit)
	var browse := Button.new()
	browse.text = "Browse…"
	h.add_child(browse)
	var clear := Button.new()
	clear.text = "Clear"
	h.add_child(clear)
	var status := Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status)
	var row := {"box": box, "edit": edit, "status": status, "check": check, "ok": true}
	edit.text_submitted.connect(func(_t): set_row(row, edit.text))
	edit.focus_exited.connect(func():
		if edit.text != row.get("checked", ""):
			set_row(row, edit.text))
	browse.pressed.connect(func(): _browse(row, label, filters))
	clear.pressed.connect(func(): set_row(row, ""))
	return row


## Puts `path` in a file row and checks it at once.
func set_row(row: Dictionary, path: String) -> void:
	row.edit.text = path
	row.checked = path
	var r: Array = [true, ""] if path == "" else row.check.call(path)
	row.ok = r[0]
	row.status.text = r[1]
	row.status.modulate = Color(0.55, 0.9, 0.55) if r[0] else Color(1, 0.5, 0.45)
	_update()


func _browse(row: Dictionary, label: String, filters: PackedStringArray) -> void:
	var d := FileDialog.new()
	d.use_native_dialog = true
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	d.title = label
	d.filters = filters
	if row.edit.text != "":
		d.current_dir = row.edit.text.get_base_dir()
	d.file_selected.connect(func(p): set_row(row, p))
	add_child(d)
	d.popup_centered(Vector2i(900, 600))


## The wizard's window: 1200×820 times the UI scale, centred (asked once it shows; ./setup starts it at 1200×820).
func _resize_window() -> void:
	await get_tree().process_frame
	var win := get_window()
	if DisplayServer.get_name() == "headless" or win.mode == Window.MODE_FULLSCREEN or win.mode == Window.MODE_EXCLUSIVE_FULLSCREEN:
		return
	# The project's 1920×1080 window is larger than most work areas, so the desktop maximizes it: back to a window.
	if win.mode != Window.MODE_WINDOWED:
		win.mode = Window.MODE_WINDOWED
		await get_tree().process_frame
	var screen := DisplayServer.screen_get_usable_rect(win.current_screen)
	# HiDPI and large screens: the UI grows with the screen (the OS scale, or the height against 1080), in steps of
	# 0.25, as long as the window still fits the work area.
	var grow := maxf(DisplayServer.screen_get_scale(win.current_screen), screen.size.y / 1080.0)
	var fit := minf(screen.size.x / 1200.0, screen.size.y / 820.0) * 0.95
	win.content_scale_factor = maxf(1.0, floorf(minf(grow, fit) * 4.0) / 4.0)
	var want := Vector2i(mini(int(1200 * win.content_scale_factor), screen.size.x), mini(int(820 * win.content_scale_factor), screen.size.y))
	DisplayServer.window_set_size(want, win.get_window_id())
	DisplayServer.window_set_position(screen.position + (screen.size - want) / 2, win.get_window_id())


## Lines stay readable in a wide window: the content is at most CONTENT_W wide, centred.
const CONTENT_W := 1100


func _cap_width() -> void:
	var side := maxi(32, int((size.x - CONTENT_W) / 2))
	margin.add_theme_constant_override("margin_left", side)
	margin.add_theme_constant_override("margin_right", side)


## The default theme with an unchecked box that shows on the dark background (a light outline).
func _theme() -> Theme:
	var t := Theme.new()
	var n := 16
	for name_color in [["unchecked", Color(0.8, 0.82, 0.86)], ["unchecked_disabled", Color(0.45, 0.46, 0.5)]]:
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var edge := x <= 1 or y <= 1 or x >= n - 2 or y >= n - 2
				img.set_pixel(x, y, name_color[1] if edge else Color(0, 0, 0, 0.25))
		t.set_icon(name_color[0], "CheckBox", ImageTexture.create_from_image(img))
	return t


# --- pages ---

func _page_requirements() -> Control:
	var v := _vbox()
	_text(v, "Setup builds the game's data from your own copy of Jane's IAF. First, what this computer has:")
	req_box = _vbox()
	v.add_child(req_box)
	var again := Button.new()
	again.text = "Check again"
	again.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	again.pressed.connect(func(): tools = IafSetup.tools(); _fill_requirements(); _update())
	v.add_child(again)
	_fill_requirements()
	return v


func _hint(arch: String, mac: String) -> String:
	return mac if OS.get_name() == "macOS" else arch


func _fill_requirements() -> void:
	for c in req_box.get_children():
		c.queue_free()
	var gpu := RenderingServer.get_video_adapter_name()
	var headless := DisplayServer.get_name() == "headless"
	var free_gb := _free_gb()
	var items := [
		[true, gpu != "" or headless, "Graphics (Vulkan)", (gpu + " — " + RenderingServer.get_video_adapter_vendor()) if gpu != "" else "no GPU renderer", "install your GPU's Vulkan driver"],
		[true, free_gb < 0 or free_gb >= BASE_GB, "Disk space", "%s free; the game data takes about %.0f GB (imagery more)" % [("%.1f GB" % free_gb) if free_gb >= 0 else "unknown", BASE_GB], "free some space on this disk"],
		[false, tools.get("gdal", false), "GDAL (optional)", "modern terrain imagery", _hint("sudo pacman -S gdal", "brew install gdal")],
		[false, tools.get("curl", false), "curl (optional)", "downloads the Survey of Israel sheets", _hint("sudo pacman -S curl", "brew install curl")],
		[false, tools.get("python3", false), "python3 (optional)", "the Survey sheets' token, the pilot guide PDFs", _hint("sudo pacman -S python", "brew install python")],
		[false, tools.get("firefox", false), "Firefox (optional)", "the Survey sheets' token, prints the pilot guide PDFs", _hint("sudo pacman -S firefox", "brew install --cask firefox")],
	]
	req_ok = true
	for it in items:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		var mark := Label.new()
		mark.text = "✓" if it[1] else ("✗" if it[0] else "–")
		mark.modulate = Color(0.55, 0.9, 0.55) if it[1] else (Color(1, 0.5, 0.45) if it[0] else Color(1, 0.8, 0.4))
		mark.custom_minimum_size.x = 24
		h.add_child(mark)
		var label := Label.new()
		label.text = it[2]
		label.custom_minimum_size.x = 220
		h.add_child(label)
		var what := Label.new()
		what.text = it[3] if it[1] else "%s — %s" % [it[3], it[4]]
		what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		what.modulate = Color(1, 1, 1, 0.75)
		h.add_child(what)
		req_box.add_child(h)
		if it[0] and not it[1]:
			req_ok = false


## Free space where assets/ is (or would be), GB; -1 when unknown.
func _free_gb() -> float:
	var dir := assets
	while dir != "" and not DirAccess.dir_exists_absolute(dir):
		var up := dir.get_base_dir()
		if up == dir:
			break
		dir = up
	var d := DirAccess.open(dir)
	return d.get_space_left() / 1e9 if d != null else -1.0


func _page_welcome() -> Control:
	var v := _vbox()
	_text(v, "Welcome. This sets up Jane's IAF: Israeli Air Force (1998) on a new engine, from your own CDs.")
	_text(v, "You need the English CD image of Jane's IAF (an .iso file). Optional: the official v1.1 patch, the Hebrew CD or the Hebrew packs, modern terrain imagery and the pilot guides.")
	_text(v, "Everything stays on this computer, in the assets folder:")
	_text(v, assets, true)
	_text(v, "The base setup takes a few minutes and about %.0f GB. You can run setup again at any time to add an extra or redo a step: only what changed runs." % BASE_GB)
	return v


func _page_cd() -> Control:
	var v := _vbox()
	_text(v, "Give the English CD image of Jane's IAF. Drop the .iso file on this window, or Browse.")
	cd_row = _file_row(v, "English CD image (required)", PackedStringArray(["*.iso, *.ISO ; CD image"]), _check_cd)
	return v


func _check_cd(path: String) -> Array:
	var r: Dictionary = IafSetup.check_cd(path)
	match r.kind:
		"english":
			return [true, "✓ The English CD of Jane's IAF."]
		"hebrew":
			return [false, "This is the Hebrew CD. The game needs the English CD here; the Hebrew CD goes on the next page."]
	return [false, "✗ Not a Jane's IAF CD image (%s)." % r.why]


func _page_optional() -> Control:
	var v := _vbox()
	_text(v, "All optional. Leave a field empty to go without it.")
	patch_row = _file_row(v, "The official v1.1 patch (iafp1_1.exe, or the downloaded update)", PackedStringArray(["*.exe, *.EXE, *.zip, *.rtp ; patch"]), _check_patch)
	hebrew_row = _file_row(v, "The Hebrew CD image (all the Hebrew briefings and menus)", PackedStringArray(["*.iso, *.ISO ; CD image"]), _check_hebrew)
	packs_box = _vbox()
	v.add_child(packs_box)
	_text(packs_box, "Without the Hebrew CD: the Hebrew packs from preflight.us (docs/packs.md).", true)
	brief_row = _file_row(packs_box, "Hebrew briefings (Brief.zip)", PackedStringArray(["*.zip ; zip"]), _check_pack.bind("brief"))
	menu_row = _file_row(packs_box, "Hebrew menus (Menu.zip)", PackedStringArray(["*.zip ; zip"]), _check_pack.bind("menu"))
	return v


func _check_patch(path: String) -> Array:
	var r: Dictionary = IafSetup.check_patch(path)
	return [true, "✓ The v1.1 patch (%d files)." % r.records] if r.ok else [false, "✗ Not the v1.1 patch (%s)." % r.why]


func _check_hebrew(path: String) -> Array:
	var r: Dictionary = IafSetup.check_cd(path)
	match r.kind:
		"hebrew":
			return [true, "✓ The Hebrew CD. The Hebrew packs are not needed."]
		"english":
			return [false, "✗ This is the English CD; the Hebrew one goes here."]
	return [false, "✗ Not a Jane's IAF CD image (%s)." % r.why]


func _check_pack(path: String, what: String) -> Array:
	var r: Dictionary = IafSetup.check_pack(path)
	if not r.ok:
		return [false, "✗ Not a Hebrew pack (%s)." % r.why]
	if r[what] == 0:
		return [false, "✗ This pack has no %s files (it holds %d briefing and %d menu files)." % [what, r.brief, r.menu]]
	return [true, "✓ %d %s files." % [r[what], "briefing" if what == "brief" else "menu"]]


func _page_extras() -> Control:
	var v := _vbox()
	_text(v, "Extras, all optional. Each can also be added later by running setup again.")
	var gdal: bool = tools.get("gdal", false)
	var need_gdal := "" if gdal else "Needs GDAL (see Requirements)."
	mapi_check = _extra(v, "Survey of Israel 2015 imagery (2 m, over Israel)",
		"Downloads the Survey's sheets from data.gov.il with curl and your Firefox's data.gov.il token (without one it opens them in your browser's tabs), then converts them. All of Israel: 79 sheets, about 17 GB of downloads (kept) and 5 GB converted, about an hour of CPU. Around the airbases: 9 sheets, about 18 minutes. Resumable.",
		"" if gdal and tools.get("curl", false) and tools.get("python3", false) else "Needs GDAL, curl and python3 (see Requirements).")
	mapi_scope = OptionButton.new()
	mapi_scope.add_item("all of Israel")
	mapi_scope.add_item("around the airbases only")
	mapi_scope.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	mapi_scope.disabled = mapi_check.disabled
	mapi_check.get_parent().add_child(mapi_scope)
	sentinel_check = _extra(v, "Sentinel-2 imagery (10 m, outside Israel)",
		"About 28 GB read over the network, about 2.5 GB on disk, about 1 h 40 min. Resumable.", need_gdal)
	refresh_check = _extra(v, "Bring the imagery up to date",
		"Converts again the imagery units that older rules made (after copying imagery from another computer).", need_gdal)
	refresh_note = refresh_check.get_parent().get_child(1)
	refresh_check.get_parent().visible = _layers().size() > 0
	guides_check = _extra(v, "Pilot guides (pictures and PDFs)",
		"Renders each jet's guide pictures with the game, then prints the PDFs with Firefox. Takes a while; the renders open game windows briefly.",
		"" if tools.get("python3", false) and tools.get("firefox", false) else "Needs python3 and Firefox (see Requirements).")
	for c in [mapi_check, sentinel_check, refresh_check, guides_check]:
		c.toggled.connect(func(_on): _update())
	return v


## An extra's checkbox with its warning; disabled with `missing` (the reason) when its tools are not here.
func _extra(parent: Control, label: String, warning: String, missing: String) -> CheckBox:
	var box := _vbox()
	box.add_theme_constant_override("separation", 2)
	parent.add_child(box)
	var c := CheckBox.new()
	c.text = label
	c.disabled = missing != ""
	box.add_child(c)
	var w := _text(box, warning if missing == "" else "%s %s" % [missing, warning], true)
	w.custom_minimum_size.x = 600
	return c


## The imagery layers on disk.
func _layers() -> PackedStringArray:
	var out := PackedStringArray()
	for id in ["sentinel2", "mapi2015"]:
		if DirAccess.dir_exists_absolute(assets.path_join("converted/imagery").path_join(id)):
			out.append(id)
	return out


## The stale-unit count for "Bring the imagery up to date", counted on a thread (sentinel2 lists over the network).
func _count_stale() -> void:
	if not refresh_check.get_parent().visible or stale_thread != null:
		return
	refresh_note.text = "Counting the units older rules made…"
	stale_thread = Thread.new()
	var a := assets
	var layers := _layers()
	stale_thread.start(func():
		var total := 0
		for id in layers:
			var n: int = IafSetup.imagery_stale(a, id)
			if n < 0:
				return -1
			total += n
		return total)


func _page_summary() -> Control:
	var v := _vbox()
	summary_label = RichTextLabel.new()
	summary_label.fit_content = true
	summary_label.bbcode_enabled = true
	summary_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(summary_label)
	return v


func _page_install() -> Control:
	var v := _vbox()
	install_note = _text(v, "")
	redo_check = CheckBox.new()
	redo_check.text = "Redo everything (also the steps that are up to date)"
	v.add_child(redo_check)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	rows_box = _vbox()
	rows_box.add_theme_constant_override("separation", 4)
	rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows_box)
	log_button = Button.new()
	log_button.text = "Show the log"
	log_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	log_button.pressed.connect(func():
		log_view.visible = not log_view.visible
		log_button.text = "Hide the log" if log_view.visible else "Show the log"
		_log_to_end.call_deferred())
	v.add_child(log_button)
	log_view = TextEdit.new()
	log_view.editable = false
	log_view.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	log_view.custom_minimum_size.y = 220
	log_view.visible = false
	v.add_child(log_view)
	return v


func _page_done() -> Control:
	var v := _vbox()
	done_label = _text(v, "")
	var start := Button.new()
	start.name = "StartGame"
	start.text = "Start the game"
	start.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	start.pressed.connect(start_game)
	v.add_child(start)
	_text(v, "Run setup again at any time (./setup, or the \"Jane's IAF (reborn) — Setup\" launcher) to add an extra or redo a step.", true)
	return v


# --- flow ---

func show_page(n: int) -> void:
	page = clampi(n, 0, PAGES.size() - 1)
	for i in pages.size():
		pages[i].visible = i == page
	title_label.text = PAGES[page]
	(find_child("Steps", true, false) as Label).text = "  ›  ".join(PAGES.map(func(p): return p if p != PAGES[page] else "[%s]" % p))
	match PAGES[page]:
		"Extras":
			_count_stale()
		"Summary":
			_fill_summary()
		"Install":
			if not running:
				_fill_rows(IafSetup.plan(JSON.stringify(inputs())), false)
				install_note.text = "Ready. Install runs the steps below; the ones whose inputs did not change are \"up to date\" and are skipped."
	_update()


func _update() -> void:
	if back_button == null:
		return
	var pg: String = PAGES[page]
	back_button.visible = page > 0 and pg != "Done"
	back_button.text = "Cancel" if running else "Back"
	back_button.disabled = false
	next_button.visible = true
	next_button.disabled = false
	match pg:
		"Requirements":
			next_button.text = "Next"
			next_button.disabled = not req_ok
		"Your CD":
			next_button.text = "Next"
			next_button.disabled = not cd_row.ok or cd_row.edit.text == ""
		"Optional":
			next_button.text = "Next"
			packs_box.visible = hebrew_row.edit.text == "" or not hebrew_row.ok
			next_button.disabled = not (patch_row.ok and hebrew_row.ok and brief_row.ok and menu_row.ok)
		"Install":
			next_button.text = "Finish" if finished else "Install"
			next_button.disabled = running or (finished and failed != "")
			redo_check.disabled = running
		"Done":
			next_button.text = "Close"
		_:
			next_button.text = "Next"
	if pg == "Extras" and mapi_scope != null:
		mapi_scope.disabled = mapi_check.disabled or not mapi_check.button_pressed


func _on_back() -> void:
	if running:
		setup.cancel()
		install_note.text = "Cancelling: the running steps stop at their next item…"
		return
	if PAGES[page] == "Install":
		finished = false
	show_page(page - 1)


func _on_next() -> void:
	match PAGES[page]:
		"Install":
			if finished:
				show_page(page + 1)
			else:
				start_install()
		"Done":
			get_tree().quit()
		_:
			show_page(page + 1)


## The inputs as setup.json's JSON (iaf_setup::to_json).
func inputs() -> Dictionary:
	var he: Variant = null
	if hebrew_row.edit.text != "":
		he = {"cd": hebrew_row.edit.text}
	elif brief_row.edit.text != "" or menu_row.edit.text != "":
		he = {"brief": brief_row.edit.text if brief_row.edit.text != "" else null, "menu": menu_row.edit.text if menu_row.edit.text != "" else null}
	var imagery := []
	if mapi_check.button_pressed and not mapi_check.disabled:
		imagery.append("mapi2015-bases" if mapi_scope.selected == 1 else "mapi2015")
	if sentinel_check.button_pressed and not sentinel_check.disabled:
		imagery.append("sentinel2")
	return {
		"cd": cd_row.edit.text,
		"patch": patch_row.edit.text if patch_row.edit.text != "" else null,
		"hebrew": he,
		"imagery": imagery,
		"refresh": refresh_check.button_pressed and not refresh_check.disabled and refresh_check.get_parent().visible,
		"guides": guides_check.button_pressed and not guides_check.disabled,
	}


## The last run's inputs (assets/setup.json) into the pages.
func _prefill() -> void:
	var text: String = IafSetup.load_inputs(assets)
	if text == "":
		return
	var i: Dictionary = JSON.parse_string(text)
	set_row(cd_row, str(i.get("cd", "")))
	if i.get("patch") != null:
		set_row(patch_row, str(i.patch))
	var he: Variant = i.get("hebrew")
	if he is Dictionary:
		if he.get("cd") != null:
			set_row(hebrew_row, str(he.cd))
		if he.get("brief") != null:
			set_row(brief_row, str(he.brief))
		if he.get("menu") != null:
			set_row(menu_row, str(he.menu))
	var imagery: Array = i.get("imagery", [])
	mapi_check.button_pressed = "mapi2015" in imagery or "mapi2015-bases" in imagery
	mapi_scope.selected = 1 if "mapi2015-bases" in imagery else 0
	sentinel_check.button_pressed = "sentinel2" in imagery
	refresh_check.button_pressed = i.get("refresh", false)
	guides_check.button_pressed = i.get("guides", false)


func _on_files_dropped(files: PackedStringArray) -> void:
	if files.is_empty():
		return
	var f := files[0]
	match PAGES[page]:
		"Your CD":
			set_row(cd_row, f)
		"Optional":
			# Where the file goes: what it is.
			if IafSetup.check_patch(f).ok:
				set_row(patch_row, f)
			elif IafSetup.check_cd(f).kind != "none":
				set_row(hebrew_row, f)
			else:
				var p: Dictionary = IafSetup.check_pack(f)
				set_row(menu_row if p.get("menu", 0) > p.get("brief", 0) else brief_row, f)


func _fill_summary() -> void:
	var i := inputs()
	var t := "[b]The English CD[/b]\n    %s\n\n" % i.cd
	t += "[b]v1.1 patch[/b]\n    %s\n\n" % (i.patch if i.patch != null else "none (the game stays v1.0)")
	var he: Variant = i.hebrew
	var he_text := "none"
	if he is Dictionary and he.get("cd") != null:
		he_text = "the Hebrew CD: %s" % he.cd
	elif he is Dictionary:
		he_text = "the packs: %s" % ", ".join([he.brief, he.menu].filter(func(x): return x != null))
	t += "[b]Hebrew[/b]\n    %s\n\n" % he_text
	var extras := []
	for m in i.imagery:
		extras.append({"sentinel2": "Sentinel-2 imagery", "mapi2015": "Survey of Israel imagery (all of Israel)", "mapi2015-bases": "Survey of Israel imagery (around the airbases)"}[m])
	if i.refresh:
		extras.append("bring the imagery up to date")
	if i.guides:
		extras.append("pilot guides")
	t += "[b]Extras[/b]\n    %s\n\n" % (", ".join(extras) if extras else "none")
	var steps: Array = IafSetup.plan(JSON.stringify(i))
	t += "[b]%d steps[/b] write into %s. Steps already done with the same inputs are skipped." % [steps.size(), assets]
	summary_label.text = t


func _fill_rows(steps: Array, keep: bool) -> void:
	if not keep:
		for c in rows_box.get_children():
			c.queue_free()
		rows.clear()
	for s in steps:
		var r: Dictionary = rows.get(s.id, {})
		if r.is_empty():
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 12)
			var title := Label.new()
			title.text = s.title
			title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			title.clip_text = true
			h.add_child(title)
			var bar := ProgressBar.new()
			bar.custom_minimum_size = Vector2(180, 12)
			bar.max_value = 1.0
			bar.show_percentage = false
			bar.modulate.a = 0.0
			h.add_child(bar)
			var state := Label.new()
			state.custom_minimum_size.x = 130
			h.add_child(state)
			rows_box.add_child(h)
			r = {"bar": bar, "state": state}
			rows[s.id] = r
		var st: String = s.get("state", "waiting")
		r.state.text = STATE_TEXT.get(st, st)
		r.state.tooltip_text = s.get("detail", "")
		r.state.modulate = {"done": Color(0.55, 0.9, 0.55), "up_to_date": Color(0.6, 0.8, 1.0), "failed": Color(1, 0.5, 0.45),
			"running": Color(1, 0.85, 0.4), "skipped": Color(1, 1, 1, 0.6)}.get(st, Color(1, 1, 1, 0.75))
		r.bar.value = s.get("fraction", 0.0)
		r.bar.modulate.a = 1.0 if st == "running" else 0.0


func start_install() -> void:
	log_view.text = ""
	_fill_rows([], false)
	failed = ""
	finished = false
	var err: String = setup.start(assets, repo, JSON.stringify(inputs()), redo_check.button_pressed, only_steps)
	if err != "":
		install_note.text = "Setup did not start: " + err
		return
	running = true
	install_note.text = "Installing…"
	_update()


func _process(_delta: float) -> void:
	if stale_thread != null and not stale_thread.is_alive() and stale_thread.is_started():
		var n: int = stale_thread.wait_to_finish()
		refresh_note.text = ("Could not count them (offline?). " if n < 0 else "%d units were made under older rules. " % n) + "Converts them again (after copying imagery from another computer)."
	if not running:
		return
	var p: Dictionary = setup.poll()
	_fill_rows(p.steps, true)
	if p.log.size() > 0:
		log_view.text += "\n".join(p.log) + "\n"
		_log_to_end.call_deferred()
	if p.done:
		running = false
		finished = true
		failed = p.error
		var up: int = p.steps.filter(func(s): return s.state == "up_to_date").size()
		install_note.text = ("Setup stopped: %s. The log has the details; fix the input and press Back, then Install again." % failed) if failed != "" \
			else "Done: %d steps ran, %d were up to date." % [p.steps.size() - up, up]
		done_label.text = "Jane's IAF is set up." if failed == "" else "Setup did not finish: " + failed
		if failed != "":
			log_view.visible = true
	_update()


## Shows the log's last lines.
func _log_to_end() -> void:
	log_view.scroll_vertical = log_view.get_v_scroll_bar().max_value


## Starts the game in a new process and closes the wizard.
func start_game() -> void:
	OS.create_process(OS.get_executable_path(), ["--path", ProjectSettings.globalize_path("res://")])
	get_tree().quit()
