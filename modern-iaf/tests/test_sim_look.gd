# The sim draws its own look (modern-iaf/sim_settings.gd PROFILE): no look switch at the 1998 game's art (which the sim
# does not have), and at Ramon's parking spot the airbase surface (the runways, taxiways and aprons of the sim's own
# airbases.json) is drawn from the first frame. The Mac run of 2026-11-08 showed no taxiway or apron: "original"
# airbases draw nothing in the sim.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_sim_look.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

## Each switch and its value meaning the original's look.
const ORIGINAL := {
	"airbases": "original",
	"sky": "original",
	"colour_grading": "original",
	"terrain_closeup": false,
	"water": false,
	"night_lights": "original",
	"particle_effects": false,
	"rolling_wheels": false,
	"hud_ladder": "original",
	"hud_style": "original",
	"real_mfds": "original",
	"models": "original",
	"cockpit_3d": "original",
	"world_scale": "original",
	"bomb_release": "original",
	"briefing_map": "original",
	"building_palette": false,
}


func run() -> void:
	var s := settings()
	if not FileAccess.file_exists(s.assets_dir().path_join("converted/modern-iaf/missions/missionlist.json")):
		print("NEEDS DATA: this test reads the sim's compiled missions (./modern-iaf-setup)")
		return
	for k in ORIGINAL:
		check(s.get(k) != ORIGINAL[k], "settings: %s is the sim's own (%s)" % [k, s.get(k)])
	var ground: GDScript = load("res://shared/terrain/ground_textures.gd")
	check(ground.available() == (s.ground_textures == "ambientcg"), "settings: ground textures follow the download")
	var bases: GDScript = load("res://shared/terrain/airbases.gd")
	check(s.airbases_file().contains("terrain/israel"), "the airbases are the sim's own (%s)" % s.airbases_file())
	load("res://flight/fly.gd").start(2011)
	var tv: Node = null
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground:
		await process_frame
		tv = current_scene
	await frames(2)
	check(bases._on, "Ramon: the airbase surface is on")
	# Town labels (look study proposal 3): on by default, drawn whenever setup wrote the places.
	var labels: GDScript = load("res://shared/terrain/town_labels.gd")
	check(s.town_labels and (tv.town_labels != null) == labels.available(), "town labels on by default")
	# Sky Levant (docs/rendering.md §1.2): the Atmospheric sky with the dusty summer's values.
	var env: Environment = tv.get_node("WorldEnvironment").environment
	var sky_mat = env.sky.sky_material if env.sky != null else null
	var ro: GDScript = load("res://shared/terrain/render_options.gd")
	var haze = sky_mat.get_shader_parameter("haze_height") if sky_mat is ShaderMaterial else null
	check(haze == ro.LEVANT.haze_height, "the sky is Levant's (haze height %s)" % haze)
	# The cockpit in its own world about the origin (cockpit_origin.gd, the Mac play test's finding 25), its eye where
	# the flight camera sits in the rig.
	var co = tv.cockpit_origin
	check(
		co != null and tv.own_bc.get_parent() == co.rig and tv.own_bc.get_viewport() == co.viewport,
		"the cockpit drawn in its own world about the origin"
	)
	if co != null:
		check(co.rig.global_position == Vector3.ZERO, "its rig at the origin")
		check(co.camera.transform.is_equal_approx(tv.camera.transform), "its eye as the flight camera's in the rig")
		check(co.camera.fov == tv.camera.fov and co.camera.near == tv.camera.near, "the same projection")
		check(
			co._quad.layers == load("res://shared/terrain/volumetric_clouds.gd").LAYER,
			"its picture on the main view's layer only (not the EO camera's)"
		)
	check(ro.terrain_grade > 0.0, "the colour grading is on (terrain_grade %.2f)" % ro.terrain_grade)
	var i: int = bases._current
	var b: Dictionary = bases.bases()[i] if i >= 0 else {}
	check(String(b.get("name", "")) == "Ramon", "Ramon: the nearest base drawn (%s)" % b.get("name", "none"))
	check(b.get("runways", []).size() > 0, "Ramon: its runways (%d)" % b.get("runways", []).size())
	var mask := Image.load_from_file(s.converted("terrain".path_join(String(b.get("mask", {}).get("file", "")))))
	var paved := 0
	if mask != null:
		mask.convert(Image.FORMAT_RGB8)
		var data := mask.get_data()
		for p in range(0, data.size(), 3 * 7):
			paved += 1 if data[p] > 0 or data[p + 1] > 0 or data[p + 2] > 0 else 0
	check(paved > 0, "Ramon: the paved mask (taxiways, aprons) has paved texels (%d sampled)" % paved)
	check(s.rejected.is_empty(), "no original data read (%s)" % [s.rejected])
