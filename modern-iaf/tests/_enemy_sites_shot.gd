# Dev helper (not run by tools/test.sh): pictures of Modern IAF's air-defence sites (docs/ai.md §15) on the Sufa's
# range: the stand-in shapes from a free camera, the cockpit while the S-300 radiates (the threat display), and a
# launch from one of its launchers. SHOT_DIR names the folder. A real render:
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> -- \
#     --log-file <temp> --resolution 1600x900 --path modern-iaf -s ../modern-iaf/tests/_enemy_sites_shot.gd
extends "res://../tests/godot/base.gd"

var tv: Node
var _cam: Camera3D
var _xf := Transform3D.IDENTITY


func _pre_draw() -> void:
	if is_instance_valid(_cam):
		_cam.global_transform = _xf
		RenderingServer.camera_set_transform(_cam.get_camera_rid(), _xf)
		_cam.set_perspective(50.0, 0.05, 30000.0)


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(OS.get_environment("SHOT_DIR").path_join(name + ".png"))
	print("saved ", name)


## The free camera `back` m from `at` (world) on bearing `brg` (degrees), `up` m above the ground, looking at it.
func _look(at: Vector3, brg: float, back: float, up: float) -> void:
	var b := deg_to_rad(brg)
	var eye := at + Vector3(sin(b), cos(b), 0) * back
	var g = tv.mission_ground(eye)
	eye.z = float(g if g != null else at.z) + up
	var tg = tv.mission_ground(at)
	var target: Vector3 = tv.world_to_scene(Vector3(at.x, at.y, float(tg if tg != null else 0.0) + 4.0))
	var e: Vector3 = tv.world_to_scene(eye)
	_xf = Transform3D(Basis.looking_at(target - e, Vector3.UP), e)


func run() -> void:
	DirAccess.make_dir_recursive_absolute(OS.get_environment("SHOT_DIR"))
	await require_data()
	var s := settings()
	s.show_info = false
	var id := sim_mission("ramon_range")
	load("res://flight/fly.gd").prepare(id)
	tv = await start_mission(id)
	s.mission_files_override = []
	tv.addon.out_dir = DirAccess.create_temp("modern-iaf-sites", false).get_current_dir()
	tv.addon.result = {"pass": true}  # the range's scorer would end the flight into the debrief
	s.invulnerable = true
	tv.addon.ui.visible = false
	var ad: Node = load("res://shared/ai/air_defence.gd").of(tv)
	var j: Vector3 = tv.player_world()
	var site_at := j + Vector3(0, 30000, 0)
	var s300: Array = ad.spawn("s300", site_at, 200.0)
	var tor: Array = ad.spawn("tor", site_at + Vector3(-320, -420, 0), 160.0)
	ad.spawn("zsu", site_at + Vector3(-200, -480, 0), 200.0)
	# The cockpit while the S-300 searches: the jet 30 km south of it, 3000 m up.
	var g = tv.mission_ground(j)
	var sp: Vector3 = tv.world_to_scene(Vector3(j.x, j.y, float(g if g != null else 0.0) + 3000.0))
	tv.rig.position = sp
	tv.flight.start(s.own_dir(), tv.player.fm_section, sp, Vector3.ZERO, Vector3(0, 0, -200), airborne_flags())
	tv.gear_down = false
	tv.throttle = 0.85
	await ground_streamed(tv, 30000, 20)
	await fly(tv, 8.0)
	await _save("enemy_sites_threat_display")
	# The stand-ins from a free camera.
	tv.in_cockpit = false
	_cam = tv.chase
	RenderingServer.frame_pre_draw.connect(_pre_draw)
	_look(tor[0].world, 240.0, 70.0, 12.0)  # the Tor near, the ZSU beside it, the S-300 behind
	await ground_streamed(tv, 30000, 20)
	await frames(60)
	await _save("enemy_sites_stand_ins")
	# A launch: the camera beside the launcher that fires.
	var site: Dictionary = ad.site_of(s300[0])
	var t0: float = tv._sim_time
	while site.flying.is_empty() and tv._sim_time - t0 < 150.0:
		_look(s300[2].world, 230.0, 90.0, 12.0)
		await fly(tv, 0.25)
	if site.flying.is_empty():
		print("no launch in 150 s")
	else:
		var fired: Dictionary = s300[2]
		for i in range(2, s300.size()):
			if site.units[i].missile == site.flying[0][0]:
				fired = s300[i]
		_look(fired.world, 230.0, 90.0, 12.0)
		await fly(tv, 0.6)
		await frames(5)
		await _save("enemy_sites_launch")
	print("RESULT PASS")
	tv.queue_free()
	await frames(3)
