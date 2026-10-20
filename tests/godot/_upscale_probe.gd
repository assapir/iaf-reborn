# Dev helper (not a test): the cost of each 3D scaling mode on mission 231 (docs/graphics-research.md §3.10). One process
# cycles every config 12 times, 90 frames each, so load from other processes hits every config alike; prints the
# median and 90th percentile frame. UP_LIVE=1: the simulation runs and only native / the two Upscaling presets are
# timed (default: frozen, every mode). UP_GFX=ssao | vol_fog | ssao_ssil adds a heavy per-pixel effect.
# UP_SHOT_DIR=dir: no timing; one shot per Upscaling choice (Settings.upscaling) as dir/upscale_<UP_TAG>_<choice>.png.
# Run on the 120 Hz screen (--screen 1 here), so the GPU sets the frame (Metal holds it at the display's refresh):
#   IAF_DEFAULT_SETTINGS=1 godot --path game --screen 1 --resolution 3840x2160 -s ../tests/godot/_upscale_probe.gd [-- --external --orbit 150 10 25]
extends "res://../tests/godot/base.gd"

const CFGS := [
	["native msaa4", 0, 1.0, true, false],
	["native none", 0, 1.0, false, false],
	["native taa", 0, 1.0, false, true],
	["mfx spatial .77 msaa4", 3, 0.77, true, false],
	["mfx spatial .67 msaa4", 3, 0.67, true, false],
	["fsr1 .77 msaa4", 1, 0.77, true, false],
	["mfx temporal .77", 4, 0.77, false, false],
	["mfx temporal .67", 4, 0.67, false, false],
	["mfx temporal .5", 4, 0.5, false, false],
	["fsr2 .77", 2, 0.77, false, false]
]


func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var tv = await start_mission(231)
	tv.frozen = OS.get_environment("UP_LIVE") != "1"
	tv.fm_stopped = tv.frozen
	var vp := tv.get_viewport()
	var env: Environment = (tv.get_node("WorldEnvironment") as WorldEnvironment).environment
	match OS.get_environment("UP_GFX"):
		"ssao":
			env.ssao_enabled = true
		"vol_fog":
			env.volumetric_fog_enabled = true
		"ssao_ssil":
			env.ssao_enabled = true
			env.ssil_enabled = true
	var shots := OS.get_environment("UP_SHOT_DIR")
	if shots != "":
		var t0 := Time.get_ticks_msec()
		while tv.terrain.missing_after_frame() and Time.get_ticks_msec() - t0 < 20000:
			await process_frame
		for u in ["off", "quality", "balanced"]:
			Settings().upscaling = u
			tv.apply_render_options()
			await frames(60)
			await RenderingServer.frame_post_draw
			root.get_viewport().get_texture().get_image().save_png(
				shots.path_join("upscale_%s_%s.png" % [OS.get_environment("UP_TAG"), u])
			)
		print("RESULT PASS")
		return
	print(
		"driver ",
		RenderingServer.get_current_rendering_driver_name(),
		" size ",
		root.size,
		" gfx ",
		OS.get_environment("UP_GFX")
	)
	await frames(120)
	var cfgs := CFGS.filter(
		func(c):
			return (
				OS.get_environment("UP_LIVE") != "1"
				or c[0] in ["native msaa4", "mfx spatial .77 msaa4", "mfx spatial .67 msaa4"]
			)
	)
	var res := {}
	for c in CFGS:
		res[c[0]] = []
	for round in 12:
		for c in cfgs:
			vp.scaling_3d_mode = c[1]
			vp.scaling_3d_scale = c[2]
			vp.msaa_3d = Viewport.MSAA_4X if c[3] else Viewport.MSAA_DISABLED
			vp.use_taa = c[4]
			await frames(30)
			var last := Time.get_ticks_usec()
			for i in 90:
				await process_frame
				var now := Time.get_ticks_usec()
				res[c[0]].append((now - last) / 1000.0)
				last = now
	for c in cfgs:
		var a: Array = res[c[0]]
		a.sort()
		print("PROBE %-24s median %6.2f ms  p90 %6.2f" % [c[0], a[a.size() / 2], a[int(a.size() * 0.9)]])
	print("RESULT PASS")
