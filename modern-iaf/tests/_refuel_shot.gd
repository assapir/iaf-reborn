# Dev helper (not run by tools/test.sh): the player's air refuelling in pictures (modern-iaf/docs/research/
# air-refuelling.md §8), every setting on (pref_choices "everything"). The Scramble start in the air of SHOT_JET (f16i
# from Ramon, f35i from Nevatim; default f16i: each jet's own Scramble mission, as the front end's), a KC-46A placed
# by the hook shared/ai/tanker.gd `place` 25 km north: the AWACS page with Vector to tanker on and its answer, the
# radio menu's Tanker page (English and Hebrew), then the request, the door, the jet held on the tanker's stations
# (tanker.gd `test_player_state`, as test_air_refuel.gd; the jet's model posed there too, its flight model stopped)
# until the boom is latched: the tanker and the jet from outside (VIEWS, each matched to a photograph's camera), the
# boom and the tanker from the cockpit. Files <SHOT_JET>_<view>.png in SHOT_DIR. A real render:
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> SHOT_JET=f35i -- \
#     --log-file <temp> --resolution 1600x900 --path modern-iaf -s ../modern-iaf/tests/_refuel_shot.gd
extends "res://../tests/godot/base.gd"

## Each jet's Scramble mission and home base (modern-iaf/data/missions/*_free.json).
const SCRAMBLE := {"f16i": ["ramon_free", "Ramon"], "f35i": ["nevatim_free", "Nevatim"]}
## The outside views, each matched to a reference photograph's camera (~/.claude/iaf-2026-pages/airrefuel/ref/, not in
## the repo): name, the camera's place (forward, right, up m in the tanker's frame) from its anchor, the anchor and
## the point looked at (nozzle, centre: the tanker's, tail: its boom hinge, mid: half way down the boom), the
## vertical field of view (deg).
const VIEWS := [
	["contact_side", Vector3(-6.0, 28.0, 2.0), "nozzle", "nozzle", 45.0],
	["contact_above_behind", Vector3(-35.0, 12.0, 14.0), "nozzle", "nozzle", 45.0],
	["tanker_side", Vector3(-2.0, -110.0, -10.0), "centre", "centre", 30.0],  # kc46_side_1
	["tanker_front_below", Vector3(55.0, 38.0, -24.0), "centre", "centre", 40.0],  # kc46_q34_1
	["tanker_below_behind", Vector3(-75.0, 0.0, -45.0), "centre", "centre", 45.0],  # boom_stowed_1
	["receiver_front_left", Vector3(25.0, -60.0, -2.0), "nozzle", "mid", 40.0],  # boom_outside_2
	["boom_close", Vector3(-1.0, 4.0, -4.0), "mid", "mid", 60.0],  # boom_outside_3
]
## The receiver's head in the cockpit for the boom (boom_from_receiver_1): yaw, pitch (deg).
const HEAD_BOOM := Vector2(-12.0, 58.0)

var tv: Node
var tk: Node
var _cam: Camera3D
var _view: Array = []
var _dir := ""
var _jet := ""


func _pre_draw() -> void:
	if not is_instance_valid(_cam) or tk == null or _view.is_empty():
		return
	var p: Dictionary = tk.tk.pose()
	var pts := {
		"nozzle": tk.tk.boom().nozzle,
		"centre": p.position,
		"tail": tv.to_local(tk._pivot.global_position),
	}
	pts["mid"] = (pts.nozzle + pts.tail) / 2.0
	var o: Vector3 = _view[1]
	var eye: Vector3 = pts[_view[2]] + p.forward * o.x + p.right * o.y + p.up * o.z
	var xf := Transform3D(Basis.looking_at(pts[_view[3]] - eye, p.up), eye)
	_cam.global_transform = tv.global_transform * xf
	RenderingServer.camera_set_transform(_cam.get_camera_rid(), _cam.global_transform)
	_cam.set_perspective(float(_view[4]), 0.5, 60000.0)


func run() -> void:
	_dir = OS.get_environment("SHOT_DIR")
	_jet = OS.get_environment("SHOT_JET") if OS.get_environment("SHOT_JET") != "" else "f16i"
	DirAccess.make_dir_recursive_absolute(_dir)
	var fly_gd: GDScript = load("res://flight/fly.gd")
	await require_data()
	var s := settings()
	var pc: Dictionary = load("res://shared/util/pref_choices.gd").preset("everything")
	for k in pc:
		s.set(k, pc[k])
	s.show_info = false
	s.invulnerable = true
	var fc := {"flight": 2, "area": "Hatzerim", "home": SCRAMBLE[_jet][1], "seed": 7, "start": "air"}
	var id := sim_mission(SCRAMBLE[_jet][0])
	fly_gd.prepare_free(id, fc)
	s.free_combat = fc
	tv = await start_mission(id)
	s.mission_files_override = []
	await fly(tv, 8.0)  # past the task call
	if tv.tanker != null:  # Scramble's own draw: this helper places its own
		tv.tanker.queue_free()
		tv.tanker = null
	var me: Vector3 = tv.player_world()
	var nose := deg_to_rad(float(tv.runtime.player_entity().get("heading", 0.0)))
	# 25 km north of the jet, clear of the darker Survey sheet south-west of Ramon (terrain.md "colour match"); the
	# jet is posed on its stations once it asks (_held).
	var ahead := me + Vector3(0.0, 25000.0, 0.0) + Vector3(sin(nose), cos(nose), 0.0) * 2000.0
	tk = load("res://shared/ai/tanker.gd").place(tv, "kc46", Vector3(ahead.x, ahead.y, 0.0), rad_to_deg(nose))
	check(tk != null, "the tanker placed")
	if tk == null:
		print("RESULT FAIL")
		return
	await ground_streamed(tv, 30000, 10)
	var sim: Node = tv.addon
	for lang in ["en", "he"]:
		s.language = lang
		sim.set_open(true)
		sim.choose(3)
		await _shot("awacs_page_" + lang)
		sim.set_open(false)
		sim.awacs_pick("vector_tanker")
		await fly(tv, 5.0)
		await _shot("awacs_vector_tanker_" + lang)
		sim.set_open(true)
		sim.choose(sim.shown.find("m:tanker") + 1)
		await _shot("radio_tanker_page_" + lang)
		sim.set_open(false)
	s.language = "en"
	await _refuel()
	print("RESULT PASS" if failures == 0 else "RESULT FAIL")


## The request, the door, the jet held on its stations until the boom is latched; then the pictures.
func _refuel() -> void:
	var me: int = tk._player_id()
	tv.flight.set_fuel(float(tv.flight.state().internal_fuel_kg) * 0.3)  # room for the pictures' minutes on the boom
	tv.addon.set_open(true)
	tv.addon.choose(tv.addon.shown.find("m:tanker") + 1)
	tv.addon.choose(1)
	tv._command([296, 1, 0])  # the door open
	var rc: Vector3 = tv.receptacle()
	tv.fm_stopped = true  # the jet's model posed on its station (_held), not flown
	tk.test_player_state = func(dt: float): return _held(rc, dt)
	var t0: float = tv._sim_time
	while not tk.in_contact() and tv._sim_time - t0 < 120.0:
		await process_frame
	check(tk.in_contact(), "%s on the boom (%s)" % [_jet, tk.said])
	tv.in_cockpit = false
	_cam = tv.chase
	RenderingServer.frame_pre_draw.connect(_pre_draw)
	await ground_streamed(tv, 30000, 10)  # the ground where the jet now is
	for v in VIEWS:
		_view = v
		await _shot(String(v[0]))
	RenderingServer.frame_pre_draw.disconnect(_pre_draw)
	tv.views.set_cockpit(tv.views.COCKPIT)  # the 3D cockpit, whatever the HUD-only preference
	tv._apply_view()
	tv.views.set_head(Vector2(deg_to_rad(HEAD_BOOM.x), deg_to_rad(HEAD_BOOM.y)))
	await _shot("boom_from_cockpit")
	tv.views.set_head(Vector2(0.0, deg_to_rad(30.0)))
	await _shot("tanker_from_cockpit")
	check(tk.in_contact() or me in Array(tk.tk.receivers()), "still with the tanker")


## The jet held with its receptacle on its station at the frame's end (test_air_refuel.gd `_held`).
func _held(rc: Vector3, dt: float) -> Dictionary:
	var st: Dictionary = tk.tk.station(tk._player_id())
	var p: Dictionary = tk.tk.pose()
	var fwd: Vector3 = Vector3(p.forward.x, 0.0, p.forward.z).normalized()
	var right: Vector3 = fwd.cross(Vector3.UP)
	var at: Vector3 = st.get("at", p.position) + p.velocity * dt
	var centre: Vector3 = at
	if String(st.get("kind", "")) == "receptacle":
		centre = at - fwd * rc.x - right * rc.y - Vector3.UP * rc.z
	tv.rig.position = centre
	tv.rig.basis = Basis(right, Vector3.UP, -fwd)
	return {"position": centre, "velocity": p.velocity, "forward": fwd, "right": right, "up": Vector3.UP}


func _shot(name: String) -> void:
	await frames(30)
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(_dir.path_join("%s_%s.png" % [_jet, name]))
	print("saved %s_%s" % [_jet, name])
