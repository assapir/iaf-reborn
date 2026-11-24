# Dev helper (not run by tools/test.sh): pictures of Scramble in flight (הזנקה, the front end's Scramble,
# modern-iaf/docs/front-end.md §2.1; docs/ai.md §23; the screen itself is _front_end_shot.gd's free): the Sufa pair
# from Ramon round Hatzerim, the first seed whose task is the MiG-29 CAP. The air start as the game makes it
# (flight/fly.gd prepare_free): the cockpit as the AWACS's task call comes, on screen (air_cockpit); the pair from
# beside the wingman (air_pair); the nearest CAP MiG-29A as the fight closes (air_mig; the player's jet invulnerable
# on its autopilot). Then the runway start: the cockpit lined up on Ramon's runway, the engine running (runway_cockpit);
# the ground start: the cockpit cold at Ramon's parking (ground_cockpit). Two still views of the ground from the air
# start, the terrain streamed round the camera: the Arava north of Hatzeva (view_arava) and the Egyptian border west
# of Ramon (view_border).
# SHOT_DIR names the folder; SHOT_LANG (en, he; en if unset) the language, in each name (air_cockpit_he). A real render:
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> -- \
#     --log-file <temp> --resolution 1600x900 --path modern-iaf -s ../modern-iaf/tests/_free_combat_shot.gd
extends "res://../tests/godot/base.gd"

const FC := {"flight": 2, "area": "Hatzerim", "home": "Ramon"}

var tv: Node
var _cam: Camera3D
var _xf := Transform3D.IDENTITY
var _follow := {}
## The free camera's place from the followed jet: right, back, up (m).
var _off := Vector3(25, 15, 6)
## A still camera (`_view`): _xf as it is.
var _still := false


func _pre_draw() -> void:
	if is_instance_valid(_cam) and _still:
		_cam.global_transform = _xf
		RenderingServer.camera_set_transform(_cam.get_camera_rid(), _xf)
		_cam.set_perspective(50.0, 0.05, 40000.0)
	elif is_instance_valid(_cam) and not _follow.is_empty():
		var at: Vector3 = tv.runtime._world_of(_follow)
		var h := deg_to_rad(float(_follow.heading))
		var fwd := Vector3(sin(h), cos(h), 0)
		var right := Vector3(cos(h), -sin(h), 0)
		var e3: Vector3 = tv.world_to_scene(at + right * _off.x - fwd * _off.y + Vector3(0, 0, _off.z))
		_xf = Transform3D(Basis.looking_at(tv.world_to_scene(at + fwd * 200.0) - e3, Vector3.UP), e3)
		_cam.global_transform = _xf
		RenderingServer.camera_set_transform(_cam.get_camera_rid(), _xf)
		_cam.set_perspective(50.0, 0.05, 40000.0)


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(OS.get_environment("SHOT_DIR").path_join("%s_%s.png" % [name, settings().language]))
	print("saved ", name)


## A still view from the world point `at` (UTM 36N m, up) along `heading`, `down` degrees below the horizon; the
## terrain's focus moved there and the ground streamed.
func _view(name: String, at: Vector3, heading: float, down: float) -> void:
	var spot := Node3D.new()
	tv.add_child(spot)
	spot.global_position = tv.world_to_scene(at)
	tv.terrain.focus = spot
	var h := deg_to_rad(heading)
	var d := deg_to_rad(down)
	var e3: Vector3 = tv.world_to_scene(at)
	var to: Vector3 = tv.world_to_scene(at + Vector3(sin(h) * cos(d), cos(h) * cos(d), -sin(d)) * 1000.0)
	_xf = Transform3D(Basis.looking_at(to - e3, Vector3.UP), e3)
	_still = true
	await ground_streamed(tv, 60000, 20)
	await frames(10)
	await _save(name)
	_still = false
	tv.terrain.focus = tv.rig
	spot.queue_free()


## Ramon's Scramble start with `start` through prepare_free, flown; the flight once its enemy is placed.
func _start(fc: Dictionary) -> Node:
	var s := settings()
	var id := sim_mission("ramon_free")
	load("res://flight/fly.gd").prepare_free(id, fc)
	s.free_combat = fc
	var v: Node = await start_mission(id)
	s.mission_files_override = []
	var node: Node = v.addon.get_node("FreeCombat")
	while node.placed.is_empty():
		await process_frame
	return v


func run() -> void:
	DirAccess.make_dir_recursive_absolute(OS.get_environment("SHOT_DIR"))
	await require_data()
	var s := settings()
	s.sim_jet = "f16i"
	s.show_info = false
	s.language = OS.get_environment("SHOT_LANG") if OS.has_environment("SHOT_LANG") else "en"
	var seed := 0
	while IafFreeCombat.roll(seed, int(s.enemy_skill())).task != "cap":
		seed += 1
	# The air start.
	tv = await _start(FC.merged({"start": "air", "seed": seed}, true))
	s.invulnerable = true
	tv._command([292, 0, 1])  # PITCH: ATT HOLD, then ALT HOLD
	tv._command([292, 0, 1])
	tv._command([292, 1, 1])  # ROLL: HDG SEL
	await ground_streamed(tv, 30000, 20)
	# As the task call shows: its subtitle waits for the speech queued before it (the wingman's contact calls).
	for i in 80:
		if tv.addon.ui.band_texts().any(func(x): return "free to engage" in x or "רשאי לתקוף" in x):
			break
		await fly(tv, 0.25)
	await frames(10)
	await _save("air_cockpit")
	tv.addon.ui.visible = false
	tv.in_cockpit = false
	_cam = tv.chase
	RenderingServer.frame_pre_draw.connect(_pre_draw)
	var wing: Array = tv.ai._ai_members.filter(func(m): return not m[1].player).map(func(m): return m[1])
	_follow = wing[0] if not wing.is_empty() else {}
	_off = Vector3(-30, 40, 8)
	await frames(30)
	await _save("air_pair")
	# The nearest CAP MiG once the fight closes (the pair flies at it), from beside it.
	var migs: Array = []
	for f in tv.ai.enemy_flights:
		migs += f.members.map(func(m): return m[1])
	var near := func() -> Dictionary:
		var best := {}
		for m in migs:
			if not m.pilot.flight.state().on_ground and int(m.state) < 3:
				if (
					best.is_empty()
					or m.world.distance_to(tv.player_world()) < best.world.distance_to(tv.player_world())
				):
					best = m
		return best
	_follow = {}
	Engine.time_scale = 4.0
	for i in 600:
		var m: Dictionary = near.call()
		if not m.is_empty() and m.world.distance_to(tv.player_world()) < 9000.0:
			break
		await fly(tv, 0.5)
	Engine.time_scale = 1.0
	var mig: Dictionary = near.call()
	print("the nearest MiG: %.0f m" % (mig.world.distance_to(tv.player_world()) if not mig.is_empty() else -1.0))
	_follow = mig
	_off = Vector3(30, 35, 6)
	await frames(30)
	await _save("air_mig")
	_follow = {}
	await _view("view_arava", Vector3(701848, 3359439, 1500), 20.0, 12.0)
	await _view("view_border", Vector3(645569, 3397341, 2600), 270.0, 14.0)
	RenderingServer.frame_pre_draw.disconnect(_pre_draw)
	s.invulnerable = false
	# The runway start.
	tv = await _start(FC.merged({"start": "runway", "seed": seed}, true))
	await ground_streamed(tv, 30000, 20)
	await fly(tv, 2.0)
	await frames(10)
	await _save("runway_cockpit")
	# The ground start.
	tv = await _start(FC.merged({"start": "ground", "seed": seed}, true))
	await ground_streamed(tv, 30000, 20)
	await fly(tv, 2.0)
	await frames(10)
	await _save("ground_cockpit")
	print("RESULT PASS")
	tv.queue_free()
	await frames(3)
