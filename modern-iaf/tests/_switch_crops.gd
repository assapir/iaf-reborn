# Dev helper (not run by tools/test.sh): the briefing's switch pictures (modern-iaf/docs/front-end.md §10). For each
# sim jet's start-up mission (2011 Sufa, 2021 Barak, 2031 Adir; parked cold, 2 s after the start, the pilot's body
# shown on the throttle only) and each step of its checklist (sim_flight.gd STEP_IDS) the head turns to the step's
# controls in the 3D cockpit (the clickable controls whose "click" is the step's command, 210 + its index; none: the
# throttle's, command 5), zoomed in, and the view around them is cropped with a ring round them, a dark view
# brightened: data/switches/<unit>/<step>.webp, 300 × 200, the switches as a cold jet has them (HIDDEN: none).
# SHOT_OUT: another folder; SHOT_MISSIONS: other missions (comma-separated menu ids).
#   flock -o ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 -- --log-file <t> \
#     --resolution 1920x1080 --path modern-iaf -s ../modern-iaf/tests/_switch_crops.gd
extends "res://tests/_switch_shot.gd"

const Look := preload("res://menu/look.gd")
## The picture's size (px) and the least part of the screen it shows (px at 1920 × 1080).
const SIZE := Vector2i(300, 200)
const MIN_VIEW := Vector2(450, 300)
## The parts' size on the screen (px) past which they are pictured in the wide view.
const BIG := Vector2(700, 450)
## The steps whose switch the eye cannot see, left to their `where` text: the F-35I's CANOPY switch (tools/f35i
## cockpit3d.py panel L4, 0.31 m aft) sits behind the seat's side.
const HIDDEN := {"f35i": ["canopy"]}


func run() -> void:
	settings().show_info = false
	var dir := OS.get_environment("SHOT_OUT")
	if dir == "":
		dir = ProjectSettings.globalize_path("res://data/switches")
	var ids := OS.get_environment("SHOT_MISSIONS")
	for id in (ids if ids != "" else "2011,2021,2031").split(","):
		load("res://flight/fly.gd").start(int(id))
		var tv: Node = null
		await process_frame
		while tv == null or tv.get("flight") == null or tv.waiting_for_ground:
			await process_frame
			tv = current_scene
		await create_timer(2.0).timeout
		tv.addon.ui.visible = false  # the checklist card and the band
		var unit: String = tv.addon.plane
		var controls: Array = tv.cockpit_3d.clickable._controls
		for c in tv.addon.rules.get("checklist", []):
			var step := str(c.step)
			var cmd: int = 210 + tv.addon.STEP_IDS.find(step)
			var parts := controls.filter(func(x): return x[1].has("click") and int(x[1].click[0]) == cmd)
			var throttle := parts.is_empty()
			if throttle:
				parts = controls.filter(func(x): return x[1].has("click") and int(x[1].click[0]) == 5)
			# The pilot's body hides the consoles' switches; his glove shows the throttle's grip.
			if tv.cockpit_3d._pilot != null:
				tv.cockpit_3d._pilot.visible = throttle
			check(not parts.is_empty(), "%s %s: a control" % [unit, step])
			if not parts.is_empty() and not step in HIDDEN.get(unit, []):
				# A drawn grip (the F-16's canopy handle, beside its throttle) hidden from the other steps' pictures.
				for x in controls:
					x[0].visible = not x[1].has("box") or x in parts
				await _crop(tv, parts.map(func(x): return x[0]), dir.path_join(unit).path_join(step + ".webp"))


## The view turned to the meshes `parts`, cropped round them with a ring, saved to `file`.
func _crop(tv: Node, parts: Array, file: String) -> void:
	var world := func() -> AABB:
		var box := AABB()
		for j in parts.size():
			var mi: MeshInstance3D = parts[j]
			var b: AABB = mi.global_transform * mi.get_aabb()
			box = b if j == 0 else box.merge(b)
		return box
	var rect := Rect2()
	# Zoomed in; a part too big for that (a throttle, a grip by the eye) in the wide view.
	for zoom in [tv.cockpit.ZOOM_MAX, tv.cockpit.ZOOM_MIN]:
		tv.cockpit.zoom = zoom
		await _aim(tv, func() -> Vector3: return world.call().get_center(), 0.0)
		var cam: Camera3D = tv.cockpit_3d.camera
		var box: AABB = world.call()
		rect = Rect2(cam.unproject_position(box.position), Vector2.ZERO)
		for k in 8:
			rect = rect.expand(cam.unproject_position(box.get_endpoint(k)))
		if rect.size.x < BIG.x and rect.size.y < BIG.y:
			break
	await RenderingServer.frame_post_draw
	var shot := get_root().get_texture().get_image()
	var screen := Vector2(shot.get_size())
	# The view: 2.2 times the parts' size, at the picture's aspect, at least MIN_VIEW, kept on the screen.
	var view := (rect.size * 2.2).max(MIN_VIEW)
	view = view.max(Vector2(view.y * SIZE.x / SIZE.y, view.x * SIZE.y / SIZE.x)).min(screen)
	var at := (rect.get_center() - view / 2.0).clamp(Vector2.ZERO, screen - view)
	var img := shot.get_region(Rect2i(at, view))
	img.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGB8)
	# A dark cockpit (the Adir's) brightened to a mean of 0.3.
	var mean := img.duplicate() as Image
	mean.resize(1, 1, Image.INTERPOLATE_BILINEAR)
	img.adjust_bcs(clampf(0.3 / maxf(mean.get_pixel(0, 0).get_luminance(), 0.01), 1.0, 2.5), 1.0, 1.0)
	var k := Vector2(SIZE) / view  # per axis: a view clamped to the screen is no longer 3:2
	var half := Vector2(SIZE) / 2.0 - Vector2(6, 6)  # the ring kept inside the picture
	var r := (rect.size * k / 2.0 * 1.3 + Vector2(8, 8)).min(half)
	_ring(img, ((rect.get_center() - at) * k).clamp(r + Vector2(4, 4), Vector2(SIZE) - r - Vector2(4, 4)), r)
	DirAccess.make_dir_recursive_absolute(file.get_base_dir())
	check(img.save_webp(file, true, 0.85) == OK, "saved " + file)
	print("crop ", file, " parts ", rect)


## An ellipse ring (3 px, the front end's accent) round `c` with half-axes `r`, smoothed at its edges.
static func _ring(img: Image, c: Vector2, r: Vector2) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var d := Vector2(x + 0.5, y + 0.5) - c
			var off := absf(Vector2(d.x / r.x, d.y / r.y).length() - 1.0) * minf(r.x, r.y)
			var a := clampf(2.0 - off, 0.0, 1.0)
			if a > 0.0:
				img.set_pixel(x, y, img.get_pixel(x, y).lerp(Look.ACCENT, a))
