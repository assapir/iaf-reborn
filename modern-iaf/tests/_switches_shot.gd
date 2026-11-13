# Dev helper (not run by tools/test.sh): every clickable part of the 3D cockpit (cockpit3d_controls.gd) lit orange in
# each jet's cold start-up flight, four views per jet (ahead and down, the left console, the right console, the left
# sill): SHOW_OUT/<jet>_<view>.jpg. The switches audit's pictures (modern-iaf/docs/cockpit.md §5.2).
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOW_OUT=<dir> -- \
#     --log-file <temp> --resolution 1280x720 --path modern-iaf -s ../modern-iaf/tests/_switches_shot.gd
extends "res://../tests/godot/base.gd"

const MISSIONS := "converted/modern-iaf/missions"
const JETS := {"f16i": "ramon_startup", "f16": "ramat_david_startup", "f35i": "nevatim_startup"}
## [name, head yaw, head pitch] (deg; + right, + up).
const HEADS := [["ahead", 0.0, -25.0], ["left", -45.0, -50.0], ["right", 45.0, -50.0], ["sill", -100.0, -35.0]]
const MARK := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, fog_disabled;
void fragment() {
	ALBEDO = vec3(1.0, 0.45, 0.0);
	ALPHA = 0.7;
}
"""


func require_data() -> void:
	if DirAccess.dir_exists_absolute(settings().own_dir().path_join("resource")):
		return
	print("NEEDS DATA: Modern IAF's own data (./modern-iaf-setup)")
	await _quit(2)
	await create_timer(3600, true, false, true).timeout


func run() -> void:
	await require_data()
	var out := OS.get_environment("SHOW_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	var fly_gd: GDScript = load("res://flight/fly.gd")
	var mark := ShaderMaterial.new()
	mark.shader = Shader.new()
	mark.shader.code = MARK
	var only := OS.get_environment("SHOW_JETS").split(",", false)  # e.g. SHOW_JETS=f35i
	for id in JETS:
		if not only.is_empty() and not id in only:
			continue
		var s := settings()
		var m: Dictionary = s.load_json(s.assets_dir().path_join(MISSIONS).path_join(JETS[id] + ".json"))
		fly_gd.set_jet(m)
		s.mission_files_override = [{"name": JETS[id], "data": m}]
		var tv: Node = await start_mission(int(m.sim.menu_id))
		s.mission_files_override = []
		await frames(30)
		var cl = tv.cockpit_3d.clickable
		cl.set_process_input(false)  # the pointer's hover leaves the marks alone
		var names := []
		for e in cl._controls:
			cl._overlay(e[0], mark)
			names.append(e[0].name)
		print("CLICKABLE %s %d: %s" % [id, names.size(), names])
		for h in HEADS:
			tv.views.snap = Vector2(deg_to_rad(h[1]), deg_to_rad(h[2]))
			await frames(20)
			await RenderingServer.frame_post_draw
			tv.get_viewport().get_texture().get_image().save_jpg(out.path_join("%s_%s.jpg" % [id, h[0]]), 0.9)
		tv.views.snap = null
	check(true, "shots in %s" % out)
