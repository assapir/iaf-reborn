# Dev helper (not run by tools/test.sh): real-render pictures of the temporal upscaler against TAA and spatial upscaling
# (docs/rendering.md §1), mission 231, the rig moved by hand at a fixed step per frame (same motion at any frame rate):
# far_<km>: the jet crossing at 250 m/s seen from a still camera 5 / 10 / 15 km off its path (crop TS_CROP px around
# it, plus the whole frame); low / chase: 60 m above the ground at 300 m/s rolling 90°/s, a fireball ahead and a
# missile trail crossing (cockpit view with the HUD; a camera behind the jet). Saves TS_OUT/<scene>_<config>.png.
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 TS_OUT=/tmp/ts -- --log-file /tmp/ts.log --path game \
#     --resolution 2560x1440 -s ../tests/godot/_temporal_shot.gd
extends "res://../tests/godot/base.gd"

## [name, Settings.antialiasing, Settings.upscaling]
const CFGS := [
	["native_taa", "taa", "off"],
	["quality_spatial", "msaa4", "quality"],
	["quality_fsr2", "temporal", "quality"],
	["native_fsr2", "temporal", "off"],
	["native_msaa", "msaa4", "off"],
]
const STEP := 1.0 / 60.0
const TS_CROP := 96

var tv: Node
var out := ""


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	out = OS.get_environment("TS_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	settings().show_info = false
	tv = await start_mission(231)
	tv.frozen = true
	tv.fm_stopped = true
	print("window ", root.size, " driver ", RenderingServer.get_current_rendering_driver_name())
	var fwd: Vector3 = -tv.rig.global_basis.z
	fwd = Vector3(fwd.x, 0, fwd.z).normalized()
	var side := fwd.cross(Vector3.UP)
	var start: Vector3 = tv.rig.global_position
	var base := Basis.looking_at(fwd, Vector3.UP)
	for c in CFGS:
		settings().antialiasing = c[1]
		settings().upscaling = c[2]
		tv.apply_render_options()
		for km in [5, 10, 15]:
			await _far(c[0], km, start, fwd, side, base)
		for view in ["low", "chase"]:
			await _low(c[0], view, start, fwd, side, base)
	print("RESULT PASS")


## The jet crossing a still camera's view `km` km off its path, 1000 m up.
func _far(cfg: String, km: int, start: Vector3, fwd: Vector3, side: Vector3, base: Basis) -> void:
	var cam := _cam()
	var p0 := _ground(start) + Vector3(0, 1000, 0)
	cam.global_position = p0 + fwd * 100.0 + side * km * 1000.0
	cam.look_at(p0 + fwd * 100.0, Vector3.UP)
	cam.make_current()
	var p := p0 - fwd * 200.0
	tv.rig.global_transform = Transform3D(base, p)
	var t0 := Time.get_ticks_msec()
	while tv.terrain.missing_after_frame() and Time.get_ticks_msec() - t0 < 15000:
		await process_frame
	for i in 120:
		tv.rig.global_transform = Transform3D(base, p)
		tv.aircraft.visible = true
		p += fwd * 250.0 * STEP
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var at := cam.unproject_position(tv.aircraft.global_position) * Vector2(img.get_size()) / Vector2(root.size)
	var r := Rect2i(Vector2i(at) - Vector2i(TS_CROP, TS_CROP) / 2, Vector2i(TS_CROP, TS_CROP))
	img.get_region(r).save_png(out.path_join("far%d_%s.png" % [km, cfg]))
	img.save_png(out.path_join("farfull%d_%s.png" % [km, cfg]))
	print("saved far%d_%s at %s" % [km, cfg, str(at)])
	cam.queue_free()
	await frames(2)


## 60 m above the ground at 300 m/s, rolling 90°/s; a fireball 500 m ahead and a missile trail crossing at 500 m/s.
func _low(cfg: String, view: String, start: Vector3, fwd: Vector3, side: Vector3, base: Basis) -> void:
	# low: the cockpit view with the HUD; chase: our camera 35 m behind and 10 m above the jet (not rolling).
	var cam: Camera3D = null if view == "low" else _cam()
	if view == "low":
		tv.views.set_cockpit(tv.views.COCKPIT)
	var p := start
	tv.rig.global_transform = Transform3D(base, _ground(p) + Vector3(0, 60, 0))
	var t0 := Time.get_ticks_msec()
	while tv.terrain.missing_after_frame() and Time.get_ticks_msec() - t0 < 15000:
		await process_frame
	var fx: Node = tv.effects
	for i in 90:
		p += fwd * 300.0 * STEP
		var g := _ground(p)
		var roll := deg_to_rad(90.0) * i * STEP
		tv.rig.global_transform = Transform3D(Basis(fwd, roll) * base, Vector3(p.x, g.y + 60.0, p.z))
		if cam != null:
			tv.aircraft.visible = true
			cam.global_position = tv.rig.global_position - fwd * 35.0 + Vector3(0, 10, 0)
			cam.look_at(tv.rig.global_position + fwd * 200.0, Vector3.UP)
		if i == 50:
			var hit := _ground(p + fwd * 500.0)
			fx.explosion(hit, fx.F_FIREBALL | fx.F_PUFF, 1.0, 5.0, hit.y)
		if tv.trails != null:
			var m := p + fwd * 600.0 - side * 400.0 + side * 500.0 * i * STEP + Vector3(0, 80, 0)
			tv.trails.emit("ts_%s_%s" % [cfg, view], m, tv.trails.MISSILE)
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out.path_join("%s_%s.png" % [view, cfg]))
	print("saved %s_%s" % [view, cfg])
	if cam != null:
		cam.queue_free()
		await frames(2)


## Our camera, kept current after terrain_view's own view update each frame; the jet drawn (chase view).
func _cam() -> Camera3D:
	var keep := GDScript.new()
	keep.source_code = "extends Camera3D\nfunc _process(_d):\n\tmake_current()\n"
	keep.reload()
	var cam := Camera3D.new()
	cam.set_script(keep)
	cam.process_priority = 1000
	cam.far = 60000.0
	tv.add_child(cam)
	tv.views.set_cockpit(tv.views.CHASE)
	cam.make_current()
	return cam


func _ground(q: Vector3) -> Vector3:
	var h = tv.terrain.height_at(q)
	return Vector3(q.x, float(h) if h != null else 0.0, q.z)
