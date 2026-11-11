# Preferences > Graphics → MORE "Clouds" (docs/rendering.md §2.1, terrain/volumetric_clouds.gd): Original by default
# (the 1998 layer of TEXTURED SKY, no volumetric node), saved and read back. Volumetric needs a RenderingDevice:
# headless has none, so it makes no node and the original layer stays (the Graphics row greys it out). The compute
# shaders compile; the history is dropped across a camera jump or a change of the sun or the layer. With a
# RenderingDevice (a real render) the node takes the layer's place on both main cameras, and its textures are made
# again at another 3D size without a double free (the Mac's "Attempted to free invalid ID", 2026-11-11). A GPU that
# cannot make the textures gets the original layer back, with one log line (the fallback only: `failed` set by hand).
# Real render: tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 -- --log-file <temp> --path iaf-reborn \
#   -s ../tests/godot/test_clouds.gd
extends "res://../tests/godot/base.gd"


## Counts the RenderingDevice's frees of an invalid RID while the test runs.
class FreeErrors:
	extends Logger
	var n := 0

	func _log_error(
		_f: String, _file: String, _l: int, code: String, why: String, _e: bool, _t: int, _b: Array[ScriptBacktrace]
	) -> void:
		if "free invalid" in why + code:
			n += 1

	func _log_message(_m: String, _e: bool) -> void:
		pass


func run() -> void:
	var s := settings()
	var vc: GDScript = load("res://shared/terrain/volumetric_clouds.gd")
	check(s.default_value("clouds") == "original" and s.clouds == "original", "Clouds: Original by default")
	s.clouds = "volumetric"
	var cfg: ConfigFile = s.write_config()
	s.clouds = "original"
	s.read_config(cfg)
	check(s.clouds == "volumetric", "Clouds is saved and read back")
	for f in ["res://shared/terrain/clouds_noise.glsl", "res://shared/terrain/clouds_march.glsl"]:
		var spirv: RDShaderSPIRV = (load(f) as RDShaderFile).get_spirv()
		check(
			spirv.compile_error_compute == "" and not spirv.bytecode_compute.is_empty(),
			"%s compiles %s" % [f.get_file(), spirv.compile_error_compute]
		)
	# The temporal history is dropped where it would show other clouds or another light (Effect._jumped).
	var ef = vc.Effect.new()
	var light := PackedFloat32Array([0.0, 1.0, 0.0, 0.3, 0.12, 0.0])
	check(ef._jumped(Vector3.ZERO, light), "the first march has no history")
	ef._prev_light = light
	var sunset := light.duplicate()
	sunset[1] = 0.999
	sunset[2] = 0.05
	var rain := light.duplicate()
	rain[5] = 1.0
	check(
		not ef._jumped(Vector3(300, 0, 0), light) and ef._jumped(Vector3(600, 0, 0), light),
		"the history holds as the camera flies on, not across a 600 m jump"
	)
	check(ef._jumped(Vector3.ZERO, sunset) and ef._jumped(Vector3.ZERO, rain), "nor across a sun or layer change")
	s.clouds = "original"
	var tv := await start_mission(311)
	await frames(3)
	check(tv.vclouds == null and tv.clouds != null, "Original: the 1998 layer, no volumetric clouds")
	s.clouds = "volumetric"
	tv.apply_render_options()
	await frames(3)
	if vc.supported():
		check(
			tv.vclouds != null and tv.clouds == null and tv.camera.compositor != null and tv.chase.compositor != null,
			"Volumetric: the raymarched clouds on both cameras in the layer's place"
		)
	else:
		check(tv.vclouds == null and tv.clouds != null, "Volumetric without a RenderingDevice: the 1998 layer stays")
	if vc.supported():
		# Resizes after the first (the window, the display or the 3D scale changed; the Mac's window settles during the
		# loading): new textures, the old freed once, no error.
		var errs := FreeErrors.new()
		OS.add_logger(errs)
		var fx = tv.vclouds.views[0].effect
		var rd := RenderingServer.get_rendering_device()
		for i in 2:
			await frames(2)
			var first: RID = fx.a_color
			fx.size = Vector2i.ONE  # as if the 3D view had changed size
			await frames(2)
			check(
				first.is_valid() and fx.a_color != first and not rd.texture_is_valid(first) and fx.retired.is_empty(),
				"resize %d makes new textures and frees the old ones" % (i + 1)
			)
			check(tv.vclouds.views[0].color.texture_rd_rid == fx.a_color, "resize %d: the new texture shown" % (i + 1))
		OS.remove_logger(errs)
		check(errs.n == 0, "no free of an invalid RID across the resizes (%d)" % errs.n)
	s.clouds = "original"
	tv.apply_render_options()
	await frames(2)
	check(
		tv.vclouds == null and tv.clouds != null and tv.camera.compositor == null,
		"back to Original: the layer, no compositor"
	)
	# A GPU that cannot make the cloud textures (Effect.failed): the original layer takes their place, for the run.
	s.clouds = "volumetric"
	var made: Node3D = vc.new()
	tv.add_child(made)
	made.attach([tv.camera, tv.chase] as Array[Camera3D])
	tv.vclouds = made
	tv.clouds.free()
	tv.clouds = null
	made.views[0].effect.failed = "a test texture"
	await frames(2)
	check(vc.unavailable and not vc.supported(), "no cloud textures: Volumetric unavailable")
	check(tv.vclouds == null and tv.clouds != null, "no cloud textures: the original layer instead")
	vc.unavailable = false
	s.clouds = "original"
