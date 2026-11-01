# Dev helper (not run by tools/test.sh): the F-16's 3D cockpit (Extras "Cockpit": 3D; docs/cockpit.md
# "3D cockpit") in a real render, the Barak's and the Sufa's: straight ahead, looking left, right and down at the MFDs
# (25° down), and the Real HUD over a ground unit 8 km ahead. C3D_LOOK=2d takes the same frames with
# the 2D panel (side by side). The scene is _cockpit_show_shot.gd's cockpit_f16_day (Settings at their defaults, the
# switch set here); C3D_HOUR=22 the night (the mission then starts at night: pass `-- --hour 22` too).
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOW_OUT=$PWD/.shots/c3d -- \
#     --log-file /tmp/c3d.log --resolution 1920x1080 --path game -s ../tests/godot/_cockpit3d_shot.gd
extends "res://../tests/godot/_cockpit_show_shot.gd"

## [name, head yaw, head pitch] (deg; + right, + up).
const HEADS := [["front", 0.0, 0.0], ["left", -80.0, -30.0], ["right", 80.0, -30.0], ["down", 0.0, -25.0]]


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	out = OS.get_environment("SHOW_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	var two_d := OS.get_environment("C3D_LOOK") == "2d"
	look = "2d" if two_d else "3d"
	settings().show_info = false
	settings().cockpit_3d = "original" if two_d else "3d"
	settings().hud_style = "real"
	var hour := float(OS.get_environment("C3D_HOUR")) if OS.get_environment("C3D_HOUR") != "" else 10.5
	for variant in ["barak", "sufa"]:
		settings().f16_variant = variant
		var spec: Array = COCKPITS.cockpit_f16_day.duplicate()
		spec[2] = hour
		await _cockpit_scene("f16_" + variant, spec)
		for h in HEADS.slice(1):
			tv.views.snap = Vector2(deg_to_rad(h[1]), deg_to_rad(h[2]))
			await _settle()
			await _shot("f16_%s_%s" % [variant, h[0]], 0.0)
		tv.views.snap = null
		await _target(variant)
	settings().jet_id = -1


## A ground unit 8 km ahead, about 11° under the nose: the Real HUD over it.
func _target(variant: String) -> void:
	var site := _ground_unit(tv)
	if site.is_empty():
		return
	var st: Dictionary = tv.flight.state()
	var w = tv.weapons
	var own: Dictionary = w.own()
	var o := {"pos": own.pos, "fwd": own.fwd}
	var p := _place(tv, w, site, o, 8000.0)
	print("target at ", p, " jet alt ", st.position)
	await _settle()
	await _shot("f16_%s_target" % variant, 0.0)
