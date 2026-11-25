# What both setup wizards share (iaf-reborn/setup/wizard.gd, modern-iaf/setup/wizard.gd; docs/setup.md,
# modern-iaf/docs/setup.md): the page machine (Back / Next / Cancel, every page scrolling in the body), the run
# through IafSetup (start, poll, cancel, the log, the background jobs, the up-to-date preview, Redo), a step's time
# left, the Attributions dialog, the free disk space, the durations the setup logs write and the window's size.
# Each game's wizard extends it with its pages, its look and its texts: `s(key)` gives the texts used here (next,
# back, cancel, cancelling, not_started, installing, log_file, show_log, hide_log, state_checking, credits), and it
# overrides _on_page, _update (calling super), _run, _polled, _finished and _finish. A release bundle's first page also
# shows the data folder (_data_folder_row; texts data_folder, change).
extends Control

var setup := IafSetup.new()
var assets := ""
var repo := ""
var tools := {}
## The pages' ids (the game's PAGES in lower case) and the one shown.
var ids: Array = []
var page := 0
var running := false
var finished := false
var failed := ""
## This run's log file: assets/logs/<log_name>-<date>-<time>.log.
var log_name := "setup"
var log_file := ""
## The background jobs running in IafSetup (begin / result): name → what handles the result.
var jobs := {}
var previews := 0
var pages: Array[Control] = []
## The Install page's step rows by id, each with at least `state` (a Label) and `redo` (its Redo tick).
var rows := {}
var title_label: Label
var back_button: Button
var next_button: Button
var log_button: Button
var install_note: Label
var redo_check: CheckBox
var log_view: TextEdit
## Started with --setup --install: the run starts at once and the game quits when it ends (_install_unattended).
var unattended := false
## Started by the front end's Update (_install_unattended): a finished run goes on to the front end.
var then_front := false


## The common start, from the game's _ready: the window `window` (times the UI scale, centred), the pages' ids, the
## assets folder, the repository and the tools this computer has.
func _start_wizard(page_ids: Array, window: Vector2i) -> void:
	ids = page_ids.map(func(p): return String(p).to_lower())
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	(func(): resize_window(self, window)).call_deferred()
	assets = Settings.assets_dir()
	repo = Settings.app_root()
	check_tools()


## The outside programs this computer has (IafSetup.tools). A bundle that ships GDAL and curl has them: not checked.
func check_tools() -> void:
	tools = IafSetup.tools()
	if Settings.ships_tools():
		tools.gdal = true
		tools.curl = true


## A release bundle's data folder, on the first page (docs/release.md): its path and Change… (a folder picker, saved
## by Settings.set_data_folder; the wizard opens again on the new folder). The checkout's assets/ is fixed: no row.
func _data_folder_row(parent: Control) -> void:
	if not Settings.bundled():
		return
	var row := HBoxContainer.new()
	row.name = "DataFolder"
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var l := Label.new()
	l.text = s("data_folder") % assets
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var b := Button.new()
	b.text = s("change")
	b.pressed.connect(_pick_data_folder)
	row.add_child(b)


func _pick_data_folder() -> void:
	var d := FileDialog.new()
	d.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.use_native_dialog = true
	d.current_dir = assets
	d.dir_selected.connect(
		func(path: String) -> void:
			if path != assets and Settings.set_data_folder(path):
				get_tree().reload_current_scene.call_deferred()
	)
	add_child(d)
	d.popup_centered(Vector2i(800, 500))


func _exit_tree() -> void:
	if running:
		setup.cancel()
	# Jobs still running end on their own (their threads only read).


## The game's text `key` (the game overrides it).
func s(key: String) -> String:
	return key


## The page shown, as its id ("welcome", "install", "done"…).
func at() -> String:
	return ids[page]


func _vbox(sep := 12) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


## The pages into `body`, each made by one of `makers` in order. A page taller than the window scrolls, so the
## footer's buttons stay in it; a page with a scroll of its own (Install's step list) keeps that one.
func _add_pages(body: Control, makers: Array) -> void:
	for f in makers:
		var p: Control = f.call()
		if p.find_children("*", "ScrollContainer", true, false).is_empty():
			var scroll := ScrollContainer.new()
			scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			p.size_flags_vertical = Control.SIZE_EXPAND_FILL
			scroll.add_child(p)
			p = scroll
		p.visible = false
		body.add_child(p)
		pages.append(p)


## The Attributions dialog over the page (its button or Esc closes it), holding `content`; mirrored with the page.
func _attributions(content: Control) -> AcceptDialog:
	var d := AcceptDialog.new()
	d.name = "Attributions"
	d.title = s("credits")
	d.exclusive = true
	var rtl := layout_direction == Control.LAYOUT_DIRECTION_RTL
	d.set_layout_direction(Window.LAYOUT_DIRECTION_RTL if rtl else Window.LAYOUT_DIRECTION_LTR)
	d.add_child(content)
	add_child(d)
	return d


# --- flow ---


func show_page(n: int) -> void:
	page = clampi(n, 0, pages.size() - 1)
	for i in pages.size():
		pages[i].visible = i == page
	_on_page(at())
	_update()


## The game's own work when page `id` shows (its title, filling it).
func _on_page(_id: String) -> void:
	pass


## The footer for the page and the run; the game's override calls it first, then sets its own.
func _update() -> void:
	if back_button == null:
		return
	var id := at()
	back_button.visible = page > 0 and id != "done"
	back_button.text = s("cancel") if running else s("back")
	log_button.visible = id == "install"
	next_button.disabled = false
	next_button.text = s("next")
	redo_check.disabled = running


func _on_back() -> void:
	if running:
		setup.cancel()
		_note(s("cancelling"))
		return
	# The front end's Update (or Updates' Always download) that failed or was cancelled: Back goes on to the game.
	if then_front:
		get_tree().change_scene_to_file.call_deferred(Settings.front_end_scene())
		return
	# Leaving Install forgets the last run: changed choices can be installed.
	if at() == "install":
		finished = false
		failed = ""
	show_page(page - 1)


func _on_next() -> void:
	match at():
		"install":
			if finished and failed == "":
				show_page(page + 1)
			else:
				start_install()
		"done":
			_finish()
		_:
			show_page(page + 1)


## Next on the Done page (the game's: start the game, or close).
func _finish() -> void:
	pass


## The Install page's status line, hidden while it is empty.
func _note(t: String) -> void:
	install_note.text = t
	install_note.visible = t != ""


## The steps to run although they are up to date: "*" for all, else the rows with Redo ticked.
func redo_ids() -> PackedStringArray:
	if redo_check.button_pressed:
		return PackedStringArray(["*"])
	return PackedStringArray(rows.keys().filter(func(id): return rows[id].redo.button_pressed))


## Install: the whole run, with full paths, also goes to the log file (kept; named in the log and when a step fails).
func start_install() -> void:
	var redo := redo_ids()
	log_view.text = ""
	failed = ""
	finished = false
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("T", "-")
	log_file = assets.path_join("logs/%s-%s.log" % [log_name, stamp])
	var err := _run(redo)
	if err != "":
		_note(s("not_started") % err)
		return
	running = true
	log_view.text = (s("log_file") % log_file) + "\n"
	_note(s("installing"))
	_update()


## `--setup --install` (docs/release.md): the run starts at once on the saved choices (the last run's, else the
## defaults), every step's end state goes to the log, and the game quits when the run ends: 0 when it finished, 1 when
## it failed or did not start. A scripted setup, and the release bundles' setup check. Called at the end of _ready.
## Also the front end's Update on a setup that changed (shared/util/updater.gd, Settings.setup_update): the run starts
## at once on the Install page, with its progress, and a finished run goes on to the front end.
func _install_unattended() -> void:
	if Settings.setup_update:
		Settings.setup_update = false
		then_front = true
		show_page(ids.find("install"))
		await get_tree().process_frame
		start_install()
		return
	if not ("--install" in OS.get_cmdline_args() or "--install" in OS.get_cmdline_user_args()):
		return
	unattended = true
	await get_tree().process_frame
	start_install()
	if not running:
		print("setup: did not start: ", install_note.text)
		get_tree().quit(1)


## Starts the game's run in IafSetup (into log_file; `redo`: redo_ids()); "" when it started, else why not.
func _run(_redo: PackedStringArray) -> String:
	return ""


## Starts IafSetup job `job` (its threads: the window stays live); `done` gets its result.
func _begin(job: String, args: Array, done: Callable) -> void:
	jobs[job] = done
	setup.begin(job, PackedStringArray(args))


## Which steps are up to date already, checked in the background as IafSetup job `kind`; `done` gets {id: up to
## date} unless a run started meanwhile. A check still running for older choices answers to nobody: its result is
## fetched and dropped, so IafSetup forgets it.
func _preview(kind: String, args: Array, done: Callable) -> void:
	for id in rows:
		rows[id].state.text = s("state_checking")
	for j in jobs:
		if j.begins_with(kind + "#"):
			jobs[j] = func(_r): pass
	previews += 1
	_begin(
		"%s#%d" % [kind, previews],
		args,
		func(up: Dictionary):
			if not running and not finished:
				done.call(up)
	)


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
	_polled(p)
	if p.log.size() > 0:
		log_view.text += "\n".join(p.log) + "\n"
		_log_to_end.call_deferred()
	if p.done:
		running = false
		finished = true
		failed = p.error
		_finished(p)
		if failed != "":
			_show_log(true)
		if unattended:
			for st in p.steps:
				print("setup: step %s: %s" % [st.id, st.state])
			print("setup: %s" % ("finished" if failed == "" else "failed: " + failed))
			get_tree().quit(0 if failed == "" else 1)
		elif then_front and failed == "":
			get_tree().change_scene_to_file.call_deferred(Settings.front_end_scene())
	_update()


## A poll of the running setup (IafSetup.poll): the game shows its steps.
func _polled(_p: Dictionary) -> void:
	pass


## The run's last poll, after it ended (`failed` holds its error, "" when it finished).
func _finished(_p: Dictionary) -> void:
	pass


## A running step's time left (s) at its pace so far, once there is one (30 s in and 2 % done); -1 before. `r` is
## its row (it keeps the start time).
static func time_left(r: Dictionary, fraction: float) -> float:
	r.started = r.get("started", Time.get_ticks_msec())
	var t: float = (Time.get_ticks_msec() - int(r.started)) / 1000.0
	return t * (1.0 - fraction) / fraction if t > 30.0 and fraction > 0.02 else -1.0


## Shows or hides the log under the step list, at its last lines.
func _show_log(on: bool) -> void:
	log_view.visible = on
	log_button.text = s("hide_log") if on else s("show_log")
	_log_to_end.call_deferred()


func _log_to_end() -> void:
	log_view.scroll_vertical = log_view.get_v_scroll_bar().max_value


## The text for this system: Linux (the distribution's package manager), macOS (Homebrew) or Windows (winget).
static func by_os(linux: String, mac: String, windows: String) -> String:
	match OS.get_name():
		"macOS":
			return mac
		"Windows":
			return windows
	return linux


## Free space where `dir` is (or would be: its nearest existing parent), GB; -1 when unknown.
static func free_gb(dir: String) -> float:
	while dir != "" and not DirAccess.dir_exists_absolute(dir):
		var up := dir.get_base_dir()
		if up == dir:
			break
		dir = up
	var d := DirAccess.open(dir)
	return d.get_space_left() / 1e9 if d != null else -1.0


## A duration as the setup logs write it (iaf_tools::progress::duration), rounded up to the minute past one; `he`:
## in Hebrew ("1:42 שעות": an abbreviation's geresh would flip about in a right-to-left line).
static func duration(sec: float, he := false) -> String:
	var t := int(round(sec))
	if t < 60:
		return ("%d שניות" if he else "%d s") % t
	if t < 3600:
		return ("%d דקות" if he else "%d min") % ceili(t / 60.0)
	return ("%d:%02d שעות" if he else "%d h %02d min") % [t / 3600, t % 3600 / 60]


## The wizard's window: `base` times the UI scale, centred on its screen. Always a framed window (a full-screen wizard
## has no title bar to close it by). HiDPI and large screens: the UI grows with the screen (the OS scale, or the height
## against 1080), in steps of 0.25, as long as the window still fits the work area. Call it deferred, from _ready.
static func resize_window(node: Node, base: Vector2i) -> void:
	await node.get_tree().process_frame
	var win := node.get_window()
	if DisplayServer.get_name() == "headless":
		return
	# The project's 1920×1080 window is larger than most work areas, so the desktop maximizes it: back to a window.
	if win.mode != Window.MODE_WINDOWED:
		win.mode = Window.MODE_WINDOWED
		await node.get_tree().process_frame
	var screen := DisplayServer.screen_get_usable_rect(win.current_screen)
	var grow := maxf(DisplayServer.screen_get_scale(win.current_screen), screen.size.y / 1080.0)
	var fit := minf(float(screen.size.x) / base.x, float(screen.size.y) / base.y) * 0.95
	win.content_scale_factor = maxf(1.0, floorf(minf(grow, fit) * 4.0) / 4.0)
	var want := Vector2i(
		mini(int(base.x * win.content_scale_factor), screen.size.x),
		mini(int(base.y * win.content_scale_factor), screen.size.y)
	)
	DisplayServer.window_set_size(want, win.get_window_id())
	DisplayServer.window_set_position(screen.position + (screen.size - want) / 2, win.get_window_id())
