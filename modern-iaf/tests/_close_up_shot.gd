# Dev helper (not run by tools/test.sh): pictures of Modern IAF's four-ship of Adirs at each spacing step (docs/ai.md
# §8.7: standard, close, tight) in level flight, and the tight four-ship breaking right. Mission ramon_four_ship with
# its jets swapped to the F-35I in memory, the flight put in the air by the dev hook ai_flights.gd `flight_in_air`,
# the steps ordered through the radio menu (Formation → Spacing). A free camera behind and above the four-ship.
# SHOT_DIR names the folder. A real render:
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> -- \
#     --log-file <temp> --resolution 1700x674 --path modern-iaf -s ../modern-iaf/tests/_close_up_shot.gd
extends "res://../tests/godot/base.gd"

const ALT := 3500.0
const SPEED := 200.0
const F16I := 1  # sim.bdb's Objects ids (0x1e)
const F35I := 3

var tv: Node
var _cam: Camera3D


## The camera behind, left of and above the lead (the 20 Nov picture's), looking at the four-ship's middle.
func _pre_draw() -> void:
	if not is_instance_valid(_cam):
		return
	var ps: Array = _jets().map(func(e): return tv.runtime._world_of(e))
	var mid := Vector3.ZERO
	for p in ps:
		mid += p / ps.size()
	var size := 0.0
	for p in ps:
		size = maxf(size, (p - mid).length())
	var lead: Vector3 = tv.player_world()
	var h := deg_to_rad(float(tv.flight.state().heading))
	var fwd := Vector3(sin(h), cos(h), 0)
	var right := Vector3(cos(h), -sin(h), 0)
	var e3: Vector3 = tv.world_to_scene(
		lead - fwd * (45.0 + size) - right * (22.0 + size * 0.5) + Vector3(0, 0, 14.0 + size * 0.4)
	)
	var xf := Transform3D(Basis.looking_at(tv.world_to_scene(mid) - e3, Vector3.UP), e3)
	_cam.global_transform = xf
	RenderingServer.camera_set_transform(_cam.get_camera_rid(), xf)
	_cam.set_perspective(60.0, 0.5, 60000.0)


func _jets() -> Array:
	return tv.ai._ai_members.map(func(m): return m[1])


func run() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	await require_data()
	var s := settings()
	s.show_info = false
	s.language = "en"
	var id := sim_mission("ramon_four_ship")
	var fly_gd = load("res://flight/fly.gd")
	fly_gd.prepare(id)
	# The four-ship of Sufas as Adirs (in memory only).
	var m: Dictionary = s.mission_files_override[0].data
	for e in m.entities.items:
		if int(e.get("0x2c6", -1)) == F16I:
			e["0x2c6"] = F35I
	s.sim_jet = "f35i"
	s.arm_loadouts = {}
	fly_gd.set_jet(m)
	tv = await start_mission(id)
	await frames(2)
	tv.addon.rules = {}  # unscored
	tv.addon.ui.visible = false
	s.invulnerable = true
	var w: Vector3 = tv.player_world()
	var g = tv.mission_ground(w)
	var pos: Vector3 = tv.world_to_scene(Vector3(w.x, w.y, float(g if g != null else 0.0) + ALT))
	tv.rig.position = pos
	tv.flight.start(s.own_dir(), tv.player.fm_section, pos, Vector3.ZERO, Vector3(SPEED, 0, 0), airborne_flags())
	tv.gear_down = false
	tv.flaps = 0.0
	tv.brakes = false
	tv.throttle = 0.55
	tv._command([292, 0, 1])  # PITCH: ATT HOLD, then ALT HOLD
	tv._command([292, 0, 1])
	tv._command([292, 1, 1])  # ROLL: HDG SEL
	await frames(2)
	tv.flight.set_ap_panel(false, false, false, 0.0, -1.0)
	if not tv.ai.flight_in_air(0.0):
		print("RESULT FAIL: the flight is not in the air")
		return
	for e in _jets():
		e.shield = true
	var fa = tv.ai.flight_ai
	Engine.time_scale = 4.0
	check(_menu(["to:0", "formation", "fingertip"]), "fingertip")
	check(await _settled(fa, 30.0), "standard: in the slots (%s)" % _errors(fa))
	await ground_streamed(tv, 30000, 10)
	tv.in_cockpit = false
	_cam = tv.chase
	RenderingServer.frame_pre_draw.connect(_pre_draw)
	await _shot(dir, "closeup_0_standard")
	for step in [1, 2]:
		check(_menu(["to:0", "formation", "m:spacing", "close_up"]), "close up")
		check(await _settled(fa, 12.0 if step == 2 else 20.0), "step %d: in the slots (%s)" % [step, _errors(fa)])
		await _shot(dir, "closeup_%d_%s" % [step, "close" if step == 1 else "tight"])
	# The turn: the lead rolls right to about 50° of bank by the stick (a held test stick, terrain_view.gd scripted_stick),
	# then pulls; past the parade's limits the flight loosens to the close step (docs/ai.md §8.7).
	Engine.time_scale = 1.0
	var worst := [0.0, 0.0, 0.0]  # each wingman's worst slot error in the break, m
	var t0: float = tv._sim_time
	var pull := -1.0  # when the pull began (sim s)
	while pull < 0.0 or tv._sim_time - pull < 6.0:
		if pull < 0.0 and (absf(float(tv.flight.state().roll)) >= 40.0 or tv._sim_time - t0 >= 4.0):
			pull = tv._sim_time
		tv.scripted_stick = Vector2(0.3, 0.0) if pull < 0.0 else Vector2(0.0, 0.2)
		for n in [2, 3, 4]:
			worst[n - 2] = maxf(worst[n - 2], float(fa.state(n).slot_error))
		await process_frame
	await _shot(dir, "closeup_3_tight_break")
	var st: Dictionary = tv.flight.state()
	print(
		"break: lead heading %.0f, roll %.1f, held step %d, %s" % [st.heading, st.roll, fa.state(2).held, _errors(fa)]
	)
	print("break: worst slot errors #2 %.1f, #3 %.1f, #4 %.1f m" % worst)
	RenderingServer.frame_pre_draw.disconnect(_pre_draw)
	print("RESULT PASS" if failures == 0 else "RESULT FAIL")
	tv.queue_free()
	await frames(3)


func _shot(dir: String, name: String) -> void:
	Engine.time_scale = 1.0
	await fly(tv, 1.0)
	await frames(30)
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(dir.path_join(name + ".png"))
	print("saved %s (%s)" % [name, _errors(tv.ai.flight_ai)])
	Engine.time_scale = 4.0


## Every wingman within `m` of its slot for 10 s (at most 240 s).
func _settled(fa, m: float) -> bool:
	var since := -1.0
	var t0: float = tv._sim_time
	while tv._sim_time - t0 < 240.0:
		var ok := [2, 3, 4].all(func(n): return float(fa.state(n).slot_error) < m)
		since = (tv._sim_time if since < 0.0 else since) if ok else -1.0
		if since >= 0.0 and tv._sim_time - since >= 10.0:
			return true
		await process_frame
	return false


func _errors(fa) -> String:
	return ", ".join([2, 3, 4].map(func(n): return "#%d %.1f m" % [n, float(fa.state(n).slot_error)]))


## The radio menu (sim_flight.gd) path picked by number, as test_four_ship.gd.
func _menu(path: Array) -> bool:
	tv.addon.set_open(true)
	for id in ["m:wingmen"] + path:
		if not id in tv.addon.shown and "m:more" in tv.addon.shown:
			tv.addon.choose(tv.addon.shown.find("m:more") + 1)
		var i: int = tv.addon.shown.find(id)
		if i < 0:
			tv.addon.set_open(false)
			return false
		tv.addon.choose(i + 1)
	return true
