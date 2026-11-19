# Dev helper (not run by tools/test.sh): the four-ship's drawing cost per AI jet in a real render (modern-iaf/docs/
# ai-plan.md F10, X5). Mission ramon_four_ship; a camera 60 m from the wingmen's shelters looks at them; the frame and
# GPU time over 600 frames (vsync off) with the three wingmen shown, then hidden; prints the difference per jet.
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 -- --log-file <temp> --path modern-iaf --resolution 1920x1080 \
#       -s ../modern-iaf/tests/_four_ship_bench_shot.gd
extends "res://../tests/godot/base.gd"


func run() -> void:
	var id := sim_mission("ramon_four_ship")
	if id < 0:
		print("NEEDS DATA: this test reads the sim's compiled missions (./modern-iaf-setup)")
		return
	load("res://flight/fly.gd").start(id)
	var tv: Node = null
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground or tv.get("addon") == null:
		await process_frame
		tv = current_scene
	await frames(30)
	var wing: Array = tv.ai.pilots.filter(func(p): return p.by_ai and p.node != null)
	check(wing.size() == 3, "three AI wingmen drawn (%d)" % wing.size())
	if wing.size() != 3:
		return
	var c := Vector3.ZERO
	for p in wing:
		c += (p.node as Node3D).global_position / 3.0
	var cam := Camera3D.new()
	tv.add_child(cam)
	cam.look_at_from_position(c + Vector3(0, 25, 55), c)
	cam.make_current()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var shown := await _measure("shown")
	for p in wing:
		p.node.visible = false
	var hidden := await _measure("hidden")
	print(
		(
			"F10 GPU: %.3f ms per AI jet drawn (frame %.3f ms per jet; 60 m off)"
			% [(shown[1] - hidden[1]) / 3.0, (shown[0] - hidden[0]) / 3.0]
		)
	)
	check(true, "bench done")


## [frame ms, GPU ms] averaged over 600 frames after 60 to settle.
func _measure(what: String) -> Array:
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	await frames(60)
	var ft := 0.0
	var gpu := 0.0
	for i in 600:
		var t := Time.get_ticks_usec()
		await process_frame
		ft += (Time.get_ticks_usec() - t) / 1000.0
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	print("BENCH wingmen %s: frame %.2f ms, GPU %.2f ms" % [what, ft / 600.0, gpu / 600.0])
	return [ft / 600.0, gpu / 600.0]
