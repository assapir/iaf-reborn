# The update on start (docs/release.md §7), both games: a dialog over the front end with Update / Later and "Don't ask
# me again"; a click outside it is Later.
#   - A release bundle looks for a newer nightly of itself for this system (the release's nightly.json). Update
#     downloads it with its progress, checks its size and SHA-256, unpacks it beside the game's folder and starts it
#     from there; that copy swaps the folders once this one has quit, starts the game again and keeps the old version
#     until the new one has started (else it puts the old one back). The logic is Rust's (iaf_setup::update).
#   - Both games, in a bundle and in the checkout, look for setup steps to run again (their stamps no longer hold:
#     iaf_setup::update::setup_stale). Update runs them in the setup wizard with its progress, then the front end.
# Preferences' Updates (Settings.update_mode): Ask (the dialog), Always download (no dialog: the update and the
# steps run at once) or Never (no check). "Don't ask me again" stores the button pressed: Update → Always download,
# Later → Never. Offline: no new version (the setup dialog still shows), play on.
# Entry: Updater.start(tree) from each game's first screen; it returns true when this start is the update's own
# (the swap) and the screen should show nothing else.
extends CanvasLayer

## The nightly's downloads (docs/release.md); $IAF_UPDATE_URL overrides it (a URL, or a folder: a local release).
const RELEASE := "https://github.com/assapir/iaf-reborn/releases/download/nightly"
const MANIFEST := "nightly.json"
## A generic User-Agent: the request carries nothing about the player.
const HEADERS := ["User-Agent: IAF-update"]
## How long the copy that swaps waits for the old game to quit, and then for the new one to start (s).
const WAIT_QUIT := 60
## Past this a first start that has not said it started is stopped and the old version goes back (a slow first
## start, e.g. macOS's first-launch check, is waited for while its program runs).
const WAIT_START := 600
const FLIGHT := "res://shared/terrain/terrain_view.tscn"

static var _started := false

var setup := IafSetup.new()
var strings := {}
## This game's version and folder (tests set them).
var own := Settings.version()
var app := ""
var os_name := OS.get_name()
var base := OS.get_environment("IAF_UPDATE_URL")
## Where the download goes: the per-user folder's updates/ (never the game's own folder).
var updates := Settings.data_home().path_join("updates")
## The release's newer download ({} none) and the setup steps to run again.
var offer := {}
var stale := []
## What runs: "" idle, "check", "download", "verify", "unpack", "swap", "failed".
var state := ""
var archive := ""
var bar: PanelContainer
## Over the screen while the dialog shows: a click on it is Later (while asking, or after a failure); while the update
## downloads and installs the game waits.
var block: ColorRect
var line: Label
var dont_ask: CheckBox
var dont_ask_note: Label
var update_button: Button
var later_button: Button
var http: HTTPRequest
var _jobs := {}


## Called once per game start by its first screen. True when this start is the update's swap (shows only its line).
static func start(tree: SceneTree) -> bool:
	if _started:
		return false
	_started = true
	var args := Array(OS.get_cmdline_args()) + Array(OS.get_cmdline_user_args())
	var u = load("res://shared/util/updater.gd").new()
	if "--update-apply" in args:
		u.state = "swap"
		tree.root.add_child.call_deferred(u)
		u.apply.call_deferred(_arg(args, "--update-apply"), int(_arg(args, "--update-pid")))
		return true
	if "--update-done" in args:
		DirAccess.make_dir_recursive_absolute(_started_file().get_base_dir())
		FileAccess.open(_started_file(), FileAccess.WRITE).store_line(Settings.version())
		IafSetup.update_finish(int(_arg(args, "--update-pid")), u.app)
	if "--update-failed" in args:
		u.state = "failed"
	elif Settings.update_mode == "never" or OS.get_environment("IAF_DEFAULT_SETTINGS") == "1" or "--mission" in args:
		u.free()
		return false
	tree.root.add_child.call_deferred(u)
	return false


## Where the new version says it started (per game: both share the per-user folder).
static func _started_file() -> String:
	return Settings.data_home().path_join("updates/started-" + Settings.project_folder())


static func _arg(args: Array, key: String) -> String:
	var i := args.find(key) + 1
	return str(args[i]) if i > 0 and i < args.size() else ""


func _init() -> void:
	layer = 100
	if base == "":
		base = RELEASE
	app = IafSetup.update_app_dir(OS.get_executable_path(), os_name)


func _ready() -> void:
	strings = Settings.strings("res://shared/util/update_strings")
	_build()
	if state == "failed":
		_show(s("failed"), false)
		return
	if state == "swap":
		return
	check()


func s(key: String) -> String:
	return str(strings.get(key, key))


func _build() -> void:
	block = ColorRect.new()
	block.color = Color(0, 0, 0, 0.5)
	block.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	block.visible = false
	block.gui_input.connect(_on_outside)
	add_child(block)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	block.add_child(center)
	bar = PanelContainer.new()
	bar.name = "UpdateBar"
	bar.visible = false
	if Settings.language == "he":
		bar.layout_direction = Control.LAYOUT_DIRECTION_RTL
	center.add_child(bar)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	bar.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 22)
	margin.add_child(box)
	line = Label.new()
	line.name = "Line"
	line.theme_type_variation = "Row"
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(line)
	dont_ask = CheckBox.new()
	dont_ask.name = "DontAsk"
	dont_ask.text = s("dont_ask")
	box.add_child(dont_ask)
	dont_ask_note = Label.new()
	dont_ask_note.theme_type_variation = "Small"
	dont_ask_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dont_ask_note.text = s("dont_ask_note")
	box.add_child(dont_ask_note)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 20)
	box.add_child(row)
	later_button = Button.new()
	later_button.name = "Later"
	later_button.theme_type_variation = "Secondary"
	later_button.text = s("later")
	later_button.pressed.connect(_on_later)
	row.add_child(later_button)
	update_button = Button.new()
	update_button.name = "Update"
	update_button.theme_type_variation = "Primary"
	update_button.text = s("update")
	update_button.pressed.connect(_on_update)
	row.add_child(update_button)


## The dialog with `text`; `ask`: with Update / Later and "Don't ask me again" (else Later alone, as Close).
func _show(text: String, ask := true) -> void:
	# The screen's normal text: its theme (Modern IAF), else the size its text has at this window's height.
	var sc := get_tree().current_scene
	if sc is Control and sc.theme != null:
		bar.theme = sc.theme
		bar.custom_minimum_size.x = 760
	else:
		var k := get_viewport().get_visible_rect().size.y / 1080.0
		bar.theme = _menu_theme(k)
		bar.custom_minimum_size.x = 760 * k
	line.text = text
	update_button.visible = ask
	dont_ask.visible = ask
	dont_ask_note.visible = ask
	later_button.text = s("later") if ask else s("close")
	block.visible = true
	bar.visible = true


## The 1998 game's front end has no theme: its setup wizard's (the menus' greys and green, its check box), the text
## sized for this window (k: its height / 1080). Modern IAF over a screen without a theme (a flight): its front end's.
func _menu_theme(k: float) -> Theme:
	if Settings.project_folder() == "modern-iaf":
		return load("res://menu/look.gd").make()
	var t: Theme = load("res://setup/wizard.gd").menu_theme()
	t.default_font_size = roundi(22 * k)
	return t


## A click outside the dialog: Later, while it asks or after a failure (never during the download and install).
func _on_outside(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and bar.visible and state in ["", "failed"]:
		_on_later()


## "Don't ask me again" ticked: the button pressed becomes Preferences' Updates.
func _keep(mode: String) -> void:
	if dont_ask.visible and dont_ask.button_pressed:
		Settings.update_mode = mode
		Settings.save()


# --- the check ---


## The release's manifest (a bundle with a nightly's version only), then the setup's stale steps.
func check() -> void:
	state = "check"
	if own.contains("-nightly."):  # a nightly; the checkout is "dev"
		_fetch_manifest()
	else:
		_check_setup()


func _fetch_manifest() -> void:
	if not base.contains("://"):
		_on_manifest(FileAccess.get_file_as_string(base.path_join(MANIFEST)))
		return
	http = HTTPRequest.new()
	http.timeout = 8.0
	add_child(http)
	http.request_completed.connect(
		func(result: int, code: int, _h, body: PackedByteArray) -> void:
			http.queue_free()
			_on_manifest(body.get_string_from_utf8() if result == OK and code == 200 else "")
	)
	if http.request(base.path_join(MANIFEST), HEADERS) != OK:
		http.queue_free()
		_on_manifest("")


## Offline or no manifest: quiet, and on to the setup's check.
func _on_manifest(text: String) -> void:
	var o: Dictionary = IafSetup.update_pick(text, Settings.project_folder(), os_name)
	if not o.is_empty() and IafSetup.update_newer(own, o.version):
		offer = o
		state = ""
		# The version kept left to right inside a Hebrew line (isolated).
		_show(s("new_version") % ["\u2066" + o.version + "\u2069", _mb(o.size)], Settings.update_mode == "ask")
		if Settings.update_mode == "always":
			download()
		return
	_check_setup()


func _check_setup() -> void:
	state = "check"
	var game := "sim" if Settings.project_folder() == "modern-iaf" else "reborn"
	_begin("setup_stale", [Settings.assets_dir(), Settings.app_root(), game], _on_stale)


func _on_stale(v) -> void:
	state = ""
	stale = v if v is Array else []
	if stale.is_empty():
		queue_free()
		return
	var bytes := 0
	var unknown := false
	for st in stale:
		if int(st.download) < 0:
			unknown = true
		bytes += maxi(0, int(st.download))
	var text := s("setup_steps_one") if stale.size() == 1 else s("setup_steps") % stale.size()
	if bytes > 0:
		text += " " + s("setup_download") % _mb(bytes)
	elif unknown:
		text += " " + s("setup_download_some")
	if Settings.update_mode == "always":
		_on_update()
		return
	_show(text)


## A size, kept left to right inside a Hebrew line (isolated), its number and unit on one line.
func _mb(bytes: int) -> String:
	return "\u2066%d\u00a0MB\u2069" % ceili(bytes / 1e6)


# --- Update / Later ---


func _on_later() -> void:
	_keep("never")
	if http != null and is_instance_valid(http):
		http.cancel_request()
	if state in ["download", "verify", "unpack"]:
		DirAccess.remove_absolute(archive)
	if not offer.is_empty() and state in ["", "failed"] and Settings.update_mode != "never":
		offer = {}
		bar.visible = false
		block.visible = false
		_check_setup()
		return
	queue_free()


func _on_update() -> void:
	_keep("always")
	if offer.is_empty():
		Settings.setup_update = true
		get_tree().change_scene_to_file.call_deferred("res://setup/wizard.tscn")
		queue_free()
		return
	download()


## The download into `updates`, with its progress on the line.
func download() -> void:
	# A data folder inside the game's folder would go with the old version.
	if _inside(Settings.assets_dir(), app):
		_fail(s("data_inside"))
		return
	IafSetup.update_cleanup(app)  # an earlier update's leftovers
	var stage: String = IafSetup.update_stage_dir(app)
	if DirAccess.make_dir_recursive_absolute(stage) != OK:
		state = "failed"
		_show(s("no_write") % app.get_base_dir(), false)
		return
	DirAccess.remove_absolute(stage)  # only the check: the unpack makes it again
	DirAccess.make_dir_recursive_absolute(updates)
	archive = updates.path_join(offer.name)
	state = "download"
	block.visible = true
	update_button.visible = false
	dont_ask.visible = false
	dont_ask_note.visible = false
	later_button.text = s("cancel")
	if not base.contains("://"):
		var err := DirAccess.copy_absolute(base.path_join(offer.name), archive)
		_downloaded(OK if err == OK else FAILED, 200)
		return
	http = HTTPRequest.new()
	http.download_file = archive
	http.download_chunk_size = 1 << 20
	add_child(http)
	http.request_completed.connect(func(result: int, code: int, _h, _b) -> void: _downloaded(result, code))
	if http.request(base.path_join(offer.name), HEADERS) != OK:
		_downloaded(FAILED, 0)


func _process(_delta: float) -> void:
	for job in _jobs.keys():
		var r: String = setup.result(job)
		if r != "":
			var done: Callable = _jobs[job]
			_jobs.erase(job)
			done.call(JSON.parse_string(r))
	if state == "download" and http != null and is_instance_valid(http):
		line.text = s("downloading") % [100.0 * http.get_downloaded_bytes() / maxf(1, offer.size), _mb(offer.size)]
	# A flight started meanwhile (a check still running, or Later not pressed): no line over it.
	var cur := get_tree().current_scene
	if cur != null and cur.scene_file_path == FLIGHT and state in ["", "check", "failed"]:
		queue_free()


func _begin(job: String, args: Array, done: Callable) -> void:
	_jobs[job] = done
	setup.begin(job, PackedStringArray(args))


## Job `job`'s answer, awaited.
func _job(job: String, args: Array) -> Variant:
	var box := []
	_begin(job, args, func(r) -> void: box.append(r))
	while box.is_empty():
		await get_tree().process_frame
	return box[0]


func _downloaded(result: int, code: int) -> void:
	if http != null and is_instance_valid(http):
		http.queue_free()
	if result != OK or code != 200:
		_fail(s("download_failed"))
		return
	state = "verify"
	line.text = s("checking")
	_begin("update_verify", [archive, str(offer.size), offer.sha256], _verified)


func _verified(err) -> void:
	if str(err) != "":
		push_warning("update: " + str(err))
		DirAccess.remove_absolute(archive)
		_fail(s("download_failed"))
		return
	state = "unpack"
	line.text = s("unpacking")
	_begin("update_unpack", [archive, app, os_name], _unpacked)


## The new version unpacked: started from there to swap the folders, this one quits.
func _unpacked(r) -> void:
	if not r is Dictionary or str(r.error) != "":
		push_warning("update: " + (str(r.error) if r is Dictionary else "no answer"))
		_fail(s("download_failed"))
		return
	var exe := str(r.dir) + OS.get_executable_path().trim_prefix(app)
	DirAccess.remove_absolute(archive)
	if OS.has_environment("IAF_UPDATE_NO_RESTART"):  # tests: the unpacked game is checked, not started
		state = "unpacked"
		return
	var args := ["--update-apply", app, "--update-pid", str(OS.get_process_id())]
	var pid: int = IafSetup.update_launch(exe, PackedStringArray(args), app.get_base_dir())
	if pid <= 0:
		_fail(s("download_failed"))
		return
	Settings.quit()


## True when folder `path` is `folder` or inside it (Windows' and macOS' paths compared without case).
func _inside(path: String, folder: String) -> bool:
	var norm := func(p: String) -> String:
		p = p.replace("\\", "/").simplify_path().trim_suffix("/")
		return p.to_lower() if os_name in ["Windows", "macOS"] else p
	var a: String = norm.call(path)
	var b: String = norm.call(folder)
	return a == b or a.begins_with(b + "/")


func _fail(text: String) -> void:
	if archive != "":
		DirAccess.remove_absolute(archive)
	state = "failed"
	_show(text, false)


# --- the copy that swaps, and the new version's first start ---


## Run from the unpacked copy: waits for the old game (`pid`) to quit, swaps the folders, starts the game from `to`,
## waits for it to say it started (_started_file), else puts the old version back.
func apply(to: String, pid: int) -> void:
	state = "swap"
	block.visible = true
	_show(s("installing"), false)
	later_button.visible = false
	var exe := to + OS.get_executable_path().trim_prefix(app)
	if not await _job("update_wait", [str(maxi(pid, 0)), str(WAIT_QUIT)]):
		push_warning("update: the old version still runs")
		_relaunch(exe, ["--update-failed"], to)
		return
	var started := _started_file()
	DirAccess.remove_absolute(started)
	var r: Dictionary = await _job("update_swap", [to, app])
	if str(r.error) != "":
		push_warning("update: " + str(r.error))
		if r.intact:
			_relaunch(exe, ["--update-failed"], to)
		else:
			_stuck(to)
		return
	var me := str(OS.get_process_id())
	var how: String = await _job(
		"update_start", [exe, to.get_base_dir(), started, str(WAIT_START), "--update-done", "--update-pid", me]
	)
	if how == "started":
		Settings.quit()
		return
	push_warning("update: the new version did not start (%s); the old one goes back" % how)
	var err: String = IafSetup.update_rollback(to)
	if err != "":
		push_warning("update: " + err)
		_stuck(to)
		return
	_relaunch(exe, ["--update-failed"], to)


## Starts the game in `to` again with `args` (from beside its folder, never inside it), and this copy quits.
func _relaunch(exe: String, args: Array, to: String) -> void:
	IafSetup.update_launch(exe, PackedStringArray(args), to.get_base_dir())
	Settings.quit()


## The old version could not be put back into `to`: the line says where it is; this copy stays until Close.
func _stuck(to: String) -> void:
	state = "failed"
	var old := to.get_base_dir().path_join(".%s.old" % to.get_file())
	_show(s("stuck") % ["\u2066" + old + "\u2069", "\u2066" + to + "\u2069"], false)
