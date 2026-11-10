# What both setup wizards share (iaf-reborn/setup/wizard.gd, modern-iaf/setup/wizard.gd; docs/setup.md,
# modern-iaf/docs/setup.md): the free disk space, the durations the setup logs write, the window's size.
extends RefCounted


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
