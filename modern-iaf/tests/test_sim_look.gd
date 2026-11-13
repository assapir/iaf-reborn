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
	# The roads: the sim's own layer (terrain/israel/roads) when setup made it, else off without a refused read.
	var roads: GDScript = load("res://shared/terrain/ground_roads.gd")
	var has_roads := FileAccess.file_exists(s.converted(s.roads_dir().path_join("main.bin")))
	var refused: int = s.rejected.size()
	check(roads.available() == has_roads, "settings: the road layer is found where the sim keeps it (%s)" % has_roads)
	check(s.rejected.size() == refused, "settings: asking for the roads reads no original path")
	check(s.ground_roads == ("detailed" if has_roads else "original"), "settings: Roads follow the sim's layer")
	# The towns in the air photo's colours (modern-iaf/docs/scenery.md §7): the buildings' shaders with SCENERY_ORTHO.
	check(s.scenery_ortho(), "settings: the sim's town look")
	var scenery_gd: GDScript = load("res://shared/terrain/scenery.gd")
	check(scenery_gd.building_shader().code.contains("#define SCENERY_ORTHO"), "the buildings' shader is the sim's")
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
	# No town labels in the sim (the 1998 game's only).
	check(not s.town_labels and tv.town_labels == null, "no town labels")
	# The ground as the original game flown at its best (the user, 2026-11-13; modern-iaf/docs/terrain.md §15): Sky
	# Atmospheric, no colour grading, the shared shader globals (one set in both projects' project.godot).
	var env: Environment = tv.get_node("WorldEnvironment").environment
	var sky_mat = env.sky.sky_material if env.sky != null else null
	var ro: GDScript = load("res://shared/terrain/render_options.gd")
	var atmos: bool = sky_mat is ShaderMaterial and sky_mat.shader.resource_path.ends_with("atmosphere.gdshader")
	check(
		s.sky == "atmospheric" and atmos and sky_mat.get_shader_parameter("haze_height") == null,
		"the sky is Atmospheric (the atmosphere shader with its own values, not Levant's)"
	)
	check(env.fog_aerial_perspective == 1.0, "the haze is the sky's (aerial perspective 1)")
	check(s.colour_grading == "original" and ro.terrain_grade == 0.0, "no colour grading (as the original game)")
	var globals := {}
	for proj: String in ["iaf-reborn", "modern-iaf"]:
		var cfg := ConfigFile.new()
		cfg.load("res://../%s/project.godot" % proj)
		var kv := {}
		for k in cfg.get_section_keys("shader_globals"):
			kv[k] = cfg.get_value("shader_globals", k)
		globals[proj] = kv
	check(globals["iaf-reborn"] == globals["modern-iaf"], "the terrain's shader globals are the original game's")
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
	await _mouse_look(tv)
	check(s.rejected.is_empty(), "no original data read (%s)" % [s.rejected])


## The mouse looks about the cockpit (Settings.cockpit_mouse_look, modern-iaf/docs/cockpit.md §2): a right drag turns
## the head, a double right-click centres it, the wheel zooms from the wide view down to the narrow one.
func _mouse_look(tv: Node) -> void:
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	tv._unhandled_input(right)
	var drag := InputEventMouseMotion.new()
	var c: Control = tv.cockpit
	drag.relative = Vector2(0.2, -0.1) * c.focal_length() / tv.MOUSE_LOOK_GAIN  # 0.2 rad right, 0.1 up
	tv._unhandled_input(drag)
	right.pressed = false
	tv._unhandled_input(right)
	check(not tv.looking and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "mouse look: the pointer back on release")
	var h: Vector2 = tv.views.head_angles()
	check(h.is_equal_approx(Vector2(0.2, 0.1)), "mouse look: a right drag right and up turns the head so (%s)" % h)
	tv.views.update(1.0)
	check(tv.views.head_angles() == h, "mouse look: the head stays where the drag left it")
	right.pressed = true
	right.double_click = true
	tv._unhandled_input(right)
	right.pressed = false
	right.double_click = false
	tv._unhandled_input(right)
	tv.views.update(10.0)
	check(tv.views.head_angles() == Vector2.ZERO, "mouse look: a double right-click centres the head")
	# The pointer never stays hidden (the Mac, 2026-11-13: "my mouse cursor isn't shows up"): a release the view did not
	# see (a Control took it, the window lost the focus) ends the look on the next frame, and so does a pause.
	right.pressed = true
	tv._unhandled_input(right)  # Input's own state: the button up
	await frames(2)
	check(not tv.looking and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "mouse look: a release unseen ends it")
	right.button_mask = MOUSE_BUTTON_MASK_RIGHT
	Input.parse_input_event(right)
	Input.flush_buffered_events()
	check(tv.looking, "mouse look: the right button held looks")
	tv._freeze(true, false)
	check(not tv.looking and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "mouse look: a pause shows the pointer")
	tv._freeze(false, false)
	right.pressed = false
	right.button_mask = 0
	Input.parse_input_event(right)
	Input.flush_buffered_events()
	var wheel := InputEventMouseButton.new()
	wheel.pressed = true
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	for i in 40:
		tv._unhandled_input(wheel)
	var narrow: float = c.get_viewport_rect().size.x / 2.0 / tan(deg_to_rad(c.VIEW_3D_NARROW_DEG) / 2.0)
	check(
		c.zoom == c.zoom_limit() and c.zoom_limit() > c.ZOOM_MAX and c.view_3d_focal() >= narrow * 0.999,
		"mouse look: the wheel zooms in to the narrow view (zoom %.2f, focal %.0f px)" % [c.zoom, c.view_3d_focal()]
	)
	# A new scroll the other way: Settings.zoom_steps drops a reverse step within ZOOM_SETTLE_MS of the last one. Waited
	# in real time: a timer's first frame can carry the time of the slow frame before it.
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 <= settings().ZOOM_SETTLE_MS:
		await process_frame
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	for i in 40:
		tv._unhandled_input(wheel)
	check(c.zoom == c.ZOOM_MIN, "mouse look: the wheel zooms out to the wide view (zoom %.2f)" % c.zoom)
