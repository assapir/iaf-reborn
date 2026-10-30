# Preferences > Graphics → MORE "Clouds" (docs/rendering.md §2.1, terrain/volumetric_clouds.gd): Original by default
# (the 1998 layer of TEXTURED SKY, no volumetric node), saved and read back. Volumetric needs a RenderingDevice:
# headless has none, so it makes no node and the original layer stays (the Graphics row greys it out). The compute
# shaders compile. With a RenderingDevice (a real render) the node takes the layer's place on both main cameras.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var s := settings()
	var vc: GDScript = load("res://terrain/volumetric_clouds.gd")
	check(s.default_value("clouds") == "original" and s.clouds == "original", "Clouds: Original by default")
	s.clouds = "volumetric"
	var cfg: ConfigFile = s.write_config()
	s.clouds = "original"
	s.read_config(cfg)
	check(s.clouds == "volumetric", "Clouds is saved and read back")
	for f in ["res://terrain/clouds_noise.glsl", "res://terrain/clouds_march.glsl"]:
		var spirv: RDShaderSPIRV = (load(f) as RDShaderFile).get_spirv()
		check(
			spirv.compile_error_compute == "" and not spirv.bytecode_compute.is_empty(),
			"%s compiles %s" % [f.get_file(), spirv.compile_error_compute]
		)
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
	s.clouds = "original"
	tv.apply_render_options()
	await frames(2)
	check(
		tv.vclouds == null and tv.clouds != null and tv.camera.compositor == null,
		"back to Original: the layer, no compositor"
	)
