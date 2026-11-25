# Dev helper (not run by tools/test.sh): pictures of the tanker (modern-iaf/docs/research/air-refuelling.md §8) with an
# AI wingman on its boom. Mission ramon_four_ship, a tanker of SHOT_TANKER (kc46, reem; default kc46) placed by the
# hook shared/ai/tanker.gd `place`, the flight in the air beside it (ai_flights.gd `flight_in_air`), "Refuel" to Kidon
# 1-2 from the radio menu; once the boom is latched, a free camera at each SHOT_VIEWS point; then the notebook raised
# at its AIR REFUEL tab in the cockpit, English and Hebrew. SHOT_DIR names the folder. A real render:
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> -- \
#     --log-file <temp> --resolution 1600x900 --path modern-iaf -s ../modern-iaf/tests/_tanker_shot.gd
extends "res://../tests/godot/base.gd"

## Each view: name, the camera's place from the tanker (forward, right, up m in its frame), what it looks at (the
## nozzle, or the tanker's centre).
const VIEWS := [
	["tanker_contact_side", Vector3(-38.0, 30.0, 2.0), "nozzle"],
	["tanker_contact_above", Vector3(-70.0, -25.0, 25.0), "nozzle"],
	["tanker_pdl_receiver", Vector3(-38.0, 0.0, -10.0), "pdl"],
	["tanker_whole", Vector3(40.0, -90.0, -15.0), "centre"],
]

var tv: Node
var tk: Node
var _cam: Camera3D
var _view := 0


func _pre_draw() -> void:
	if not is_instance_valid(_cam) or tk == null:
		return
	var p: Dictionary = tk.tk.pose()
	var v: Array = VIEWS[_view]
	var o: Vector3 = v[1]
	var eye: Vector3 = p.position + p.forward * o.x + p.right * o.y + p.up * o.z
	var at: Vector3 = p.position
	if v[2] == "nozzle":
		at = tk.tk.boom().nozzle
	elif v[2] == "pdl":
		at = p.position + p.forward * 15.0 - p.up * 3.0
	var xf := Transform3D(Basis.looking_at(at - eye, p.up), eye)
	_cam.global_transform = tv.global_transform * xf
	RenderingServer.camera_set_transform(_cam.get_camera_rid(), _cam.global_transform)
	_cam.set_perspective(50.0, 0.5, 60000.0)


func run() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	await require_data()
	var s := settings()
	s.show_info = false
	s.language = "en"
	var id := sim_mission("ramon_four_ship")
	tv = await start_mission(id)
	await frames(2)
	tv.addon.rules = {}
	tv.addon.ui.visible = false
	s.invulnerable = true
	var kind := OS.get_environment("SHOT_TANKER")
	var w: Vector3 = tv.player_world()
	tk = load("res://shared/ai/tanker.gd").place(
		tv, kind if kind != "" else "kc46", Vector3(w.x, w.y - 20000.0, 0), 0.0
	)
	var p: Dictionary = tk.tk.pose()
	var pos: Vector3 = p.position - p.forward * 600.0 - p.right * 300.0
	tv.rig.position = pos
	tv.flight.start(s.own_dir(), tv.player.fm_section, pos, Vector3.ZERO, Vector3(246.9, 0, 0), airborne_flags())
	tv.gear_down = false
	tv.flaps = 0.0
	tv.throttle = 0.7
	tv._command([292, 0, 1])
	tv._command([292, 0, 1])
	tv._command([292, 1, 1])
	await frames(2)
	if not tv.ai.flight_in_air(0.0):
		print("RESULT FAIL: the flight is not in the air")
		return
	for m in tv.ai._ai_members:
		if not m[1].player:
			m[1].shield = true
			m[1].pilot.flight.set_fuel(float(m[1].pilot.flight.state().internal_fuel_kg) - 2000.0)
	tv.addon.set_open(true)
	for id2 in ["m:wingmen", "to:2", "refuel"]:
		tv.addon.choose(tv.addon.shown.find(id2) + 1)
	Engine.time_scale = 4.0
	var t0: float = tv._sim_time
	while not tk.said.any(func(c): return c[0] == "contact") and tv._sim_time - t0 < 900.0:
		await process_frame
	Engine.time_scale = 1.0
	check(tk.in_contact() or tk.contact_id == 2, "Kidon 1-2 on the boom (%s)" % [tk.said])
	await ground_streamed(tv, 30000, 10)
	tv.in_cockpit = false
	_cam = tv.chase
	RenderingServer.frame_pre_draw.connect(_pre_draw)
	for i in VIEWS.size():
		_view = i
		await frames(20)
		await RenderingServer.frame_post_draw
		var img := root.get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		img.save_png(dir.path_join(VIEWS[i][0] + ".png"))
		print("saved ", VIEWS[i][0])
	RenderingServer.frame_pre_draw.disconnect(_pre_draw)
	# The notebook raised at its AIR REFUEL tab in the cockpit, the door open (modern-iaf/docs/training.md §11).
	tv.in_cockpit = true
	tv.addon.ui.visible = true
	tv._command([296, 1, 0])
	var kb: Node = tv.addon.kneeboard
	kb.set_raised(true)
	for lang in ["en", "he"]:
		s.language = lang
		await frames(3)
		kb.refresh()
		kb.board.open("refuel", 0)
		await frames(20)
		await RenderingServer.frame_post_draw
		var img := root.get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		img.save_png(dir.path_join("notebook_refuel_%s.png" % lang))
		print("saved notebook_refuel_", lang)
	s.language = "en"
	print("RESULT PASS" if failures == 0 else "RESULT FAIL")
	tv.queue_free()
	await frames(3)
