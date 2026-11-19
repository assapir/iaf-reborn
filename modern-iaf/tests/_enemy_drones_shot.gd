# Dev helper (not run by tools/test.sh): pictures of Modern IAF's one-way attack drones (docs/ai.md §16) on the Sufa's
# range: a drone in flight from a free camera above and beside it, and the cockpit about 8 km behind it with the radar
# on (the drone a contact on the FCR, then locked). SHOT_DIR names the folder. A real render:
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> -- \
#     --log-file <temp> --resolution 1600x900 --path modern-iaf -s ../modern-iaf/tests/_enemy_drones_shot.gd
extends "res://../tests/godot/base.gd"

var tv: Node
var _cam: Camera3D
var _xf := Transform3D.IDENTITY
var _follow := {}


func _pre_draw() -> void:
	if is_instance_valid(_cam):
		_look(_follow, 9.0, -1.0, 5.0)
		_cam.global_transform = _xf
		RenderingServer.camera_set_transform(_cam.get_camera_rid(), _xf)
		_cam.set_perspective(40.0, 0.05, 30000.0)


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(OS.get_environment("SHOT_DIR").path_join(name + ".png"))
	print("saved ", name)


## The free camera beside drone `e`: `side` m to its right and `back` m behind, `up` m above it, looking at it.
func _look(e: Dictionary, side: float, back: float, up: float) -> void:
	var at: Vector3 = tv.runtime._world_of(e)
	var h := deg_to_rad(float(e.heading))
	var fwd := Vector3(sin(h), cos(h), 0)
	var right := Vector3(cos(h), -sin(h), 0)
	var eye: Vector3 = at + right * side - fwd * back + Vector3(0, 0, up)
	var e3: Vector3 = tv.world_to_scene(eye)
	_xf = Transform3D(Basis.looking_at(tv.world_to_scene(at) - e3, Vector3.UP), e3)


func run() -> void:
	DirAccess.make_dir_recursive_absolute(OS.get_environment("SHOT_DIR"))
	await require_data()
	var s := settings()
	s.show_info = false
	var id := sim_mission("ramon_range")
	load("res://flight/fly.gd").prepare(id)
	tv = await start_mission(id)
	s.mission_files_override = []
	tv.addon.out_dir = DirAccess.create_temp("modern-iaf-drones", false).get_current_dir()
	tv.addon.result = {"pass": true}  # the range's scorer would end the flight into the debrief
	s.invulnerable = true
	tv.addon.ui.visible = false
	var w = tv.weapons
	var j: Vector3 = tv.player_world()
	var salvo: Dictionary = load("res://shared/ai/drones.gd").of(tv).spawn([j, j + Vector3(0, 60000, 0)], 1)
	# The cockpit 9 km behind it at 150 m/s, the radar on (Q).
	var g = tv.mission_ground(j)
	var sp: Vector3 = tv.world_to_scene(Vector3(j.x, j.y - 9000.0, float(g if g != null else 0.0) + 700.0))
	tv.rig.position = sp
	tv.flight.start(s.own_dir(), tv.player.fm_section, sp, Vector3.ZERO, Vector3(0, 0, -150), airborne_flags())
	tv.gear_down = false
	tv.throttle = 0.85
	var e := InputEventKey.new()
	e.keycode = KEY_Q
	e.physical_keycode = KEY_Q
	e.pressed = true
	tv._unhandled_input(e)
	await ground_streamed(tv, 30000, 20)
	# A full frame of the FCR's search, then the drone locked (the HUD's target box on it).
	var d: Dictionary = salvo.ents[0]
	var t0: float = tv._sim_time
	while tv._sim_time - t0 < 20.0 and not w.radar.contacts.any(func(c): return c.key == d.key):
		await fly(tv, 0.5)
	w.radar.lock_key(String(d.key))
	await fly(tv, 1.5)
	print("radar contacts: ", w.radar.contacts.map(func(c): return c.key), " locked: ", w.radar.locked().get("key", ""))
	await _save("enemy_drone_on_radar")
	# The drone from a free camera beside it.
	tv.in_cockpit = false
	_follow = d
	_cam = tv.chase
	RenderingServer.frame_pre_draw.connect(_pre_draw)
	await frames(60)
	await _save("enemy_drone_in_flight")
	print("RESULT PASS")
	tv.queue_free()
	await frames(3)
