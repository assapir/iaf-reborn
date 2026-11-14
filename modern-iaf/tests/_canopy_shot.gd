# Real-render pictures of the canopy at a cold start (modern-iaf/docs/training.md §7.1): each jet's start-up from
# outside and from the seat (its default view) with the canopy up, halfway down after its step and shut:
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> -- --log-file <temp> --path modern-iaf \
#     --resolution 1600x900 -s ../modern-iaf/tests/_canopy_shot.gd
# Writes SHOT_DIR/<jet>_<view>_{up,mid,shut}.png for each outside view (OUT_VIEWS) and seat view (SEAT_VIEWS), see
# _both. SHOT_JETS: some of them (comma-separated: sufa,barak,adir). SHOT_MID: the canopy's opening for "mid" (0.5).
extends "res://../tests/godot/base.gd"

const JETS := {2011: "sufa", 2021: "barak", 2031: "adir"}


## Puts `cam` at `eye` looking at `at` after everything else each frame.
class Placer:
	extends Node
	var cam: Camera3D
	var eye: Vector3
	var at: Vector3

	func _init() -> void:
		process_priority = 1000

	func _process(_delta: float) -> void:
		cam.look_at_from_position(eye, at, Vector3.UP)


func run() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	var s := settings()
	s.show_info = false
	var only := _env("SHOT_JETS", ",".join(JETS.values())).split(",")
	for id in JETS:
		var jet: String = JETS[id]
		if not jet in only:
			continue
		load("res://flight/fly.gd").start(id)
		var tv: Node = null
		await process_frame
		while tv == null or tv.get("flight") == null or tv.waiting_for_ground or tv.get("addon") == null:
			await process_frame
			tv = current_scene
		await frames(30)
		check(tv.aircraft.canopy_open == 1.0, "%s: the canopy up at the cold start" % jet)
		await _both(tv, dir, jet, "up")
		tv.addon.start_step(5)
		var t0 := Time.get_ticks_msec()
		var mid := float(_env("SHOT_MID", "0.5"))
		while tv.aircraft.canopy_open > mid and Time.get_ticks_msec() - t0 < 30000:
			await process_frame
		check(tv.aircraft.canopy_open <= mid, "%s: halfway down" % jet)
		tv.addon.set_process(false)  # the canopy held halfway for both pictures (sim_flight.gd _canopy)
		await _both(tv, dir, jet, "mid")
		tv.addon.set_process(true)
		while tv.aircraft.canopy_open > 0.0 and Time.get_ticks_msec() - t0 < 60000:
			await process_frame
		check(tv.aircraft.canopy_open == 0.0, "%s: shut" % jet)
		await _both(tv, dir, jet, "shut")


## The outside pictures from the chase camera placed by us (OUT_VIEWS: name:azimuth:elevation in degrees:distance in
## m, about the canopy; azimuth 0 ahead of the nose, 90 the left side, 180 behind), then the seat's (SEAT_VIEWS:
## name:yaw:pitch in degrees, the head turned).
func _both(tv: Node, dir: String, jet: String, stage: String) -> void:
	if tv.addon.get("kneeboard") != null:
		tv.addon.kneeboard.set_raised(false)  # the notebook stowed: it covers the jet's right side
	tv.in_cockpit = false
	tv.views.set_orbit(tv.rig, tv.CHASE_OFFS, 1.0, tv.views.CHASE, false)
	var a: Node3D = tv.aircraft
	var part = a.parts.get("Canopy", a.parts.get("canopy"))
	var at: Vector3 = (part.node as Node3D).global_position if part != null else a.global_position
	var cam: Camera3D = tv.chase
	for v in _env("OUT_VIEWS", "out:135:25:9").split(","):
		var f := v.split(":")
		var az := deg_to_rad(float(f[1]))
		var el := deg_to_rad(float(f[2]))
		var d := Vector3(-sin(az) * cos(el), sin(el), -cos(az) * cos(el))
		var eye: Vector3 = at + a.global_basis.orthonormalized() * d * float(f[3])
		# The chase camera placed after the views place it, every frame.
		var place := Placer.new()
		place.cam = cam
		place.eye = eye
		place.at = at
		tv.add_child(place)
		await frames(10)
		await _shot(dir, "%s_%s_%s" % [jet, f[0], stage])
		place.queue_free()
	tv.in_cockpit = true
	tv.views.set_cockpit(tv.views.COCKPIT)
	for v in _env("SEAT_VIEWS", "in:0:0").split(","):
		var f := v.split(":")
		await frames(5)
		tv.views.head = Vector2(deg_to_rad(float(f[1])), deg_to_rad(float(f[2])))
		await frames(10)
		await _shot(dir, "%s_%s_%s" % [jet, f[0], stage])
	tv.views.head = Vector2.ZERO


func _shot(dir: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	check(get_root().get_texture().get_image().save_png(dir.path_join(name + ".png")) == OK, "saved " + name)


func _env(name: String, default: String) -> String:
	return OS.get_environment(name) if OS.get_environment(name) != "" else default
