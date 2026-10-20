# Dev helper (not a test): the cost and look of one Godot rendering feature switched on in a flight, for
# docs/graphics-research.md. GFX = none | ssao | ssil | sdfgi | glow | vol_fog | shadows_off | shadows_hq | fsr_0.67 |
# all_light. Mission 311 at Ramat David, the rig GFX_ALT m up (default 60) looking along the base, flown ahead for 10 s:
# the average / p95 frame; then a shot to GFX_SHOT. Run at 3840x2160 with GFX_SCALE (e.g. 1.6) so the GPU, not the display's
# refresh (Metal presents at it even with vsync off; Godot reports no GPU time on Metal), sets the frame.
#   GFX=ssao GFX_SHOT=/tmp/ssao.png IAF_DEFAULT_SETTINGS=1 godot --path game --resolution 3840x2160 -s ../tests/godot/_gfx_proto.gd
extends "res://../tests/godot/base.gd"


func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var tv = await start_mission(311)
	tv.frozen = true
	tv.fm_stopped = true
	await frames(30)
	var env: Environment = (
		tv.get_viewport().world_3d.environment if tv.get_viewport().world_3d.environment != null else null
	)
	if env == null:
		for n in tv.find_children("*", "WorldEnvironment", true, false):
			env = n.environment
	var sun: DirectionalLight3D = tv.get_node("Sun")
	var what := OS.get_environment("GFX")
	match what:
		"ssao":
			env.ssao_enabled = true
		"ssil":
			env.ssil_enabled = true
		"sdfgi":
			env.sdfgi_enabled = true
		"glow":
			env.glow_enabled = true
		"vol_fog":
			env.volumetric_fog_enabled = true
			env.volumetric_fog_density = 0.002
		"shadows_off":
			sun.shadow_enabled = false
		"shadows_hq":
			sun.shadow_enabled = true
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			RenderingServer.directional_shadow_atlas_set_size(8192, true)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
		"fsr_0.67":
			tv.get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			tv.get_viewport().scaling_3d_scale = 0.67
		"all_light":
			env.ssao_enabled = true
			env.ssil_enabled = true
			env.glow_enabled = true
	# GFX_SCALE: the 3D render scale (e.g. 1.6), to load the GPU past the display's refresh, where Metal holds the frame.
	if OS.get_environment("GFX_SCALE") != "" and what != "fsr_0.67":
		tv.get_viewport().scaling_3d_scale = float(OS.get_environment("GFX_SCALE"))
	print("GFX %s: shadows %s, msaa %d" % [what, sun.shadow_enabled, tv.get_viewport().msaa_3d])
	var g = tv.terrain.height_at(tv.rig.position)
	var alt := float(OS.get_environment("GFX_ALT")) if OS.get_environment("GFX_ALT") != "" else 60.0
	tv.rig.position.y = (g if g != null else 0.0) + alt
	tv.rig.basis = Basis.from_euler(Vector3(deg_to_rad(-6.0), deg_to_rad(-30.0), 0.0), EULER_ORDER_YXZ)
	tv._apply_view()
	var t0 := Time.get_ticks_msec()
	while tv.terrain.missing_after_frame() and Time.get_ticks_msec() - t0 < 20000:
		await process_frame
	await frames(60)
	var times: Array[float] = []
	var fwd: Vector3 = -tv.rig.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var start := Time.get_ticks_usec()
	var last := start
	while Time.get_ticks_usec() - start < 10_000_000:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		tv.rig.position += fwd * 120.0 * (now - last) / 1e6
		last = now
	var sorted := times.duplicate()
	sorted.sort()
	var avg := 0.0
	for t in times:
		avg += t
	avg /= times.size()
	print(
		"GFX %-12s frame %6.2f ms (p95 %6.2f)  %5.1f fps" % [what, avg, sorted[int(times.size() * 0.95)], 1000.0 / avg]
	)
	if OS.get_environment("GFX_SHOT") != "":
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png(OS.get_environment("GFX_SHOT"))
	print("RESULT PASS")
