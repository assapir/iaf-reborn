# Dev helper (not run by tools/test.sh): the pictures of the sim's pilot guides (modern-iaf/docs/guides/<unit>.md), real
# renders of each jet's 3D cockpit from its take-off mission: shots/<unit>/cockpit.webp (on its parking spot, the engine
# at idle and the avionics up, the head straight ahead) and shots/<unit>/hud.webp (in the air 300 m above the ground
# at 150 m/s, gear up: the HUD, the F-35I's helmet display). 1280 × 720 WebP, written into modern-iaf/docs/guides/shots
# (GUIDE_OUT another folder; GUIDE_JETS=f16i,f35i some jets).
#   ~/tmp/fe-render.sh / flock -o ~/.cache/iaf-gpu-bench.lock timeout -k 10 900 tools/godot_window.sh \
#     IAF_DEFAULT_SETTINGS=1 [GUIDE_JETS=f16i] -- --log-file <temp> --resolution 1920x1080 --path modern-iaf \
#     -s ../modern-iaf/tests/_guide_shot.gd
extends "res://tests/test_mvp.gd"

## Each jet's take-off mission (its base's).
const GUIDE_MISSIONS := {"f16i": "ramon_takeoff", "f16d": "ramat_david_takeoff", "f35i": "nevatim_takeoff"}


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	await require_data()
	fly_gd = load("res://flight/fly.gd")
	out = OS.get_temp_dir().path_join("iaf2026-guide-%d" % OS.get_process_id())
	settings().show_info = false
	var dir := OS.get_environment("GUIDE_OUT")
	if dir == "":
		dir = ProjectSettings.globalize_path("res://docs/guides/shots")
	var want := Array(OS.get_environment("GUIDE_JETS").split(",", false))
	for unit in GUIDE_MISSIONS:
		if not want.is_empty() and not unit in want:
			continue
		var tv := await _start(GUIDE_MISSIONS[unit])
		# The engine and the avionics up by the one command (Start engine), at the probe's time scale.
		tv._command([200, 0, 0])
		var up := func() -> bool: return float(tv.flight.state().rpm) >= 0.59 and bool(tv.flight.state().avionics)
		check(await _until(tv, up, 150.0), "%s: the engine at idle, the avionics up" % unit)
		Engine.time_scale = 1.0
		tv.views.snap = Vector2.ZERO
		await fly(tv, 2.0)
		await _shot(dir.path_join(unit), "cockpit")
		# In the air: an airborne start 300 m above the ground, 150 m/s on the jet's heading, gear up.
		var st0: Dictionary = tv.flight.state()
		var g = tv.terrain.height_at(st0.position)
		var pos: Vector3 = st0.position + Vector3(0, 300.0 + float(g if g != null else 0.0) - st0.position.y, 0)
		tv.rig.position = pos
		tv.flight.start(
			settings().own_dir(),
			tv.player.fm_section,
			pos,
			Vector3(0, 0, st0.heading),
			st0.forward * 150.0,
			airborne_flags()
		)
		tv.gear_down = false
		tv.throttle = 0.8
		tv.brakes = false
		await fly(tv, 2.0)
		await _shot(dir.path_join(unit), "hud")


func _shot(dir: String, name: String) -> void:
	await frames(3)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.resize(1280, 720, Image.INTERPOLATE_LANCZOS)
	DirAccess.make_dir_recursive_absolute(dir)
	var p := dir.path_join(name + ".webp")
	img.save_webp(p, true, 0.85)
	print("shot ", p)
