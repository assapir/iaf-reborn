# Dev helper (not run by tools/test.sh): the Settings' Off / On pictures (modern-iaf/docs/front-end.md §14.1), our own
# renders. For each graphics setting in data/settings/previews.json ([its low choice, its high choice]) the sim's
# take-off mission is flown twice with the preset High but for that setting, the jet moved over Tel Aviv at 350 m in
# the cockpit view, and the left half of the first picture is joined to the right half of the second:
# data/settings/<setting>.webp, 840 × 472 (the pane shows it at 560 × 315; Antialiasing and Upscaling the view's middle
# at the screen's own pixels). PREVIEW_ONLY=<setting,...> takes those.
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 -- --log-file <temp> \
#     --path modern-iaf --resolution 1920x1080 -s ../modern-iaf/tests/_settings_previews.gd
extends "res://tests/_flight_bench.gd"

const SIZE := Vector2i(840, 472)
## The place and the view: engine metres (UTM) over Tel Aviv's towers, the height (m), heading and pitch (deg).
const AT := Vector2(668000, 3550689)
const ALT := 350.0
const HEADING := -30.0
const PITCH := -8.0
## The settings pictured at the screen's own pixels (the middle of the view, not scaled down): the edges' smoothing.
const CROP := ["antialiasing", "upscaling"]


func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var s := settings()
	var dir := ProjectSettings.globalize_path("res://data/settings")
	var pairs: Dictionary = s.load_json(dir.path_join("previews.json"))
	var only := OS.get_environment("PREVIEW_ONLY").split(",", false)
	var high: Dictionary = load("res://shared/util/pref_choices.gd").PRESETS.high
	s.blackbox = false
	s.show_info = false
	for key in pairs:
		if not only.is_empty() and not only.has(key):
			continue
		var halves := []
		for v in pairs[key]:
			for k in high:
				s.set(k, high[k])
			s.set(key, v)
			halves.append(await _picture(key in CROP))
		var out := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGB8)
		out.blit_rect(halves[0], Rect2i(0, 0, SIZE.x / 2, SIZE.y), Vector2i.ZERO)
		out.blit_rect(halves[1], Rect2i(SIZE.x / 2, 0, SIZE.x / 2, SIZE.y), Vector2i(SIZE.x / 2, 0))
		var path := dir.path_join(key + ".webp")
		check(out.save_webp(path, true, 0.7) == OK, "saved " + path)


## The view with the settings now: a fresh flight, the jet placed, the ground streamed; the picture cut to 16:9 and
## scaled to SIZE, or with `crop` its middle SIZE at the screen's pixels.
func _picture(crop: bool) -> Image:
	if current_scene != null:
		unload_current_scene()  # the last flight freed first, so start_mission waits for the new one
		await frames(3)
	var tv: Node = await start_mission(0)
	tv.apply_render_options()
	tv.frozen = true
	tv.fm_stopped = true
	tv.addon.ui.visible = false
	tv.rig.position = tv.world_to_scene(Vector3(AT.x, AT.y, 0))
	var g = tv.terrain.height_at(tv.rig.position)
	tv.rig.position.y = (g if g != null else 0.0) + ALT
	tv.rig.basis = Basis.from_euler(Vector3(deg_to_rad(PITCH), deg_to_rad(HEADING), 0.0), EULER_ORDER_YXZ)
	tv._apply_view()
	await ground_streamed(tv, 20000)
	await seconds(4.0)  # the scenery's towns and the shadows settle
	var img := root.get_viewport().get_texture().get_image()
	if crop:
		var c := (Vector2i(img.get_width(), img.get_height()) - SIZE) / 2
		img = img.get_region(Rect2i(c, SIZE))
		img.convert(Image.FORMAT_RGB8)
		return img
	var h := mini(img.get_height(), img.get_width() * 9 / 16)
	img = img.get_region(Rect2i(0, (img.get_height() - h) / 2, img.get_width(), h))
	img.convert(Image.FORMAT_RGB8)
	img.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_LANCZOS)
	return img
